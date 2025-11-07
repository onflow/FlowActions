import "EVM"

import "ERC4626PriceOracles"

access(all)
fun main(vaultHex: String, assetIdentifier: String): UFix64? {
    let vault = EVM.addressFromString(vaultHex)
    let asset = CompositeType(assetIdentifier) ?? panic("Invalid asset identifier: \(assetIdentifier)")
    let oracle = ERC4626PriceOracles.PriceOracle(
        vault: vault,
        asset: asset,
        uniqueID: nil
    )
    return oracle.price(ofToken: asset)
}
