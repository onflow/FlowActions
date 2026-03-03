import "FungibleToken"
import "SwapFactory"
import "StableSwapFactory"
import "SwapInterfaces"
import "SwapConfig"
import "SwapError"

transaction(
    token0Key: String,
    token1Key: String,
    token0InDesired: UFix64,
    token1InDesired: UFix64,
    token0InMin: UFix64,
    token1InMin: UFix64,
    deadline: UFix64,
    token0VaultPath: StoragePath,
    token1VaultPath: StoragePath,
    stableMode: Bool
) {

    let pairAddr: Address
    let pairPublicRef: &{SwapInterfaces.PairPublic}
    let token0Vault: @{FungibleToken.Vault}
    let token1Vault: @{FungibleToken.Vault}
    let lpTokenCollectionRef: &SwapFactory.LpTokenCollection

    prepare(signer: auth(Storage, Capabilities) &Account) {
        assert(deadline >= getCurrentBlock().timestamp, message:
            SwapError.ErrorEncode(
                msg: "AddLiquidity: expired \(deadline.toString()) < \(getCurrentBlock().timestamp.toString())",
                err: SwapError.ErrorCode.EXPIRED
            )
        )
        // get the SwapPair address for the given tokens & stable mode
        self.pairAddr = (stableMode) ? 
            StableSwapFactory.getPairAddress(token0Key: token0Key, token1Key: token1Key) ?? panic("AddLiquidity: nonexistent stable pair \(token0Key) <-> \(token1Key) create stable pair first")
            :
            SwapFactory.getPairAddress(token0Key: token0Key, token1Key: token1Key) ?? panic("AddLiquidity: nonexistent pair \(token0Key) <-> \(token1Key) create pair first")
        self.pairPublicRef = getAccount(self.pairAddr).capabilities.borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)!

        /*
            pairInfo = [
                SwapPair.token0Key,
                SwapPair.token1Key,
                SwapPair.token0Vault.balance,
                SwapPair.token1Vault.balance,
                SwapPair.account.address,
                SwapPair.totalSupply
            ]
        */
        let pairInfo = self.pairPublicRef.getPairInfo()
        var token0In = 0.0
        var token1In = 0.0
        var token0Reserve = 0.0
        var token1Reserve = 0.0
        if token0Key == (pairInfo[0] as! String) {
            token0Reserve = (pairInfo[2] as! UFix64)
            token1Reserve = (pairInfo[3] as! UFix64)
        } else {
            token0Reserve = (pairInfo[3] as! UFix64)
            token1Reserve = (pairInfo[2] as! UFix64)
        }
        if token0Reserve == 0.0 && token1Reserve == 0.0 {
            token0In = token0InDesired
            token1In = token1InDesired
        } else {
            var amount1Optimal = SwapConfig.quote(amountA: token0InDesired, reserveA: token0Reserve, reserveB: token1Reserve)
            if (amount1Optimal <= token1InDesired) {
                assert(amount1Optimal >= token1InMin, message:
                    SwapError.ErrorEncode(
                        msg: "SLIPPAGE_OFFSET_TOO_LARGE expect min\(token1InMin.toString()) got \(amount1Optimal.toString())",
                        err: SwapError.ErrorCode.SLIPPAGE_OFFSET_TOO_LARGE
                    )
                )
                token0In = token0InDesired
                token1In = amount1Optimal
            } else {
                var amount0Optimal = SwapConfig.quote(amountA: token1InDesired, reserveA: token1Reserve, reserveB: token0Reserve)
                assert(amount0Optimal <= token0InDesired)
                assert(amount0Optimal >= token0InMin, message:
                    SwapError.ErrorEncode(
                        msg: "SLIPPAGE_OFFSET_TOO_LARGE expect min\(token0InMin.toString()) got \(amount0Optimal.toString())",
                        err: SwapError.ErrorCode.SLIPPAGE_OFFSET_TOO_LARGE
                    )
                )
                token0In = amount0Optimal
                token1In = token1InDesired
            }
        }
        
        // withdraw the liquidity for each Vault
        let token0Source = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: token0VaultPath)
            ?? panic("Signer does not have token0Vault \(token0Key) at provided path \(token0VaultPath)")
        let token1Source = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: token1VaultPath)
            ?? panic("Signer does not have token1Vault \(token1Key) at provided path \(token1VaultPath)")
        self.token0Vault <- token0Source.withdraw(amount: token0In)
        self.token1Vault <- token1Source.withdraw(amount: token1In)
        
        // get a reference to the signer's LpTokenCollection
        let lpTokenCollectionStoragePath = SwapConfig.LpTokenCollectionStoragePath
        let lpTokenCollectionPublicPath = SwapConfig.LpTokenCollectionPublicPath
        let storedType = signer.storage.type(at: lpTokenCollectionStoragePath)
        if storedType == nil {
            // configure LpTokenCollection if none found
            signer.storage.save(<-SwapFactory.createEmptyLpTokenCollection(), to: lpTokenCollectionStoragePath)
            let lpTokenCollectionCap = signer.capabilities.storage.issue<&{SwapInterfaces.LpTokenCollectionPublic}>(
                    lpTokenCollectionStoragePath
                )
            signer.capabilities.publish(lpTokenCollectionCap, at: lpTokenCollectionPublicPath)
        }
        self.lpTokenCollectionRef = signer.storage.borrow<&SwapFactory.LpTokenCollection>(from: lpTokenCollectionStoragePath)
            ?? panic("Mistyped \(storedType!.identifier) resource found in storage at \(lpTokenCollectionStoragePath) where LpTokenCollection expected")
    }

    execute {
        let lpTokenVault <- self.pairPublicRef.addLiquidity(
            tokenAVault: <- self.token0Vault,
            tokenBVault: <- self.token1Vault
        )
        self.lpTokenCollectionRef.deposit(pairAddr: self.pairAddr, lpTokenVault: <- lpTokenVault)
    }
}