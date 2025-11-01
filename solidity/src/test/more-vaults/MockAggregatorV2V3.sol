// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAggregatorV2V3Interface} from "../../../lib/More-Vaults/src/interfaces/Chainlink/IAggregatorV2V3Interface.sol";

/**
 * @title MockAggregatorV2V3
 * @dev Minimal Chainlink-style price feed used together with {MockAaveOracle}.
 *
 * Usage in tests:
 *  - Deploy the mock with the desired decimals (pass 0 to use 8) and optional description label (empty string => "Mock Feed").
 *  - Call {updateAnswer} prior to using the feed so `latestRoundData` returns a non-zero price and timestamp.
 *  - Wire the feed address into {MockAaveOracle.setAssetSource} for each asset under test.
 *
 * Only the latest round is meaningful in this mock; historical lookups revert for unanswered rounds.
 */
contract MockAggregatorV2V3 is IAggregatorV2V3Interface {
    error NoDataPresent(uint80 roundId);
    error InvalidAnswer();

    struct RoundData {
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
    }

    string private _description;
    uint8 private _decimals;
    uint80 private _latestRoundId;

    mapping(uint80 => RoundData) private _rounds;

    constructor(uint8 decimals_, string memory description_) {
        _decimals = decimals_ == 0 ? 8 : decimals_;
        _description = bytes(description_).length == 0 ? "Mock Feed" : description_;
    }

    // --------------------------------------------------------------------
    // Configuration helpers
    // --------------------------------------------------------------------

    /// @notice Publish a new price. Provide a timestamp (block.timestamp recommended) for downstream freshness checks.
    ///         Passing 0 uses the current block timestamp.
    /// @param answer Price value represented with {decimals()} precision. Must be positive.
    /// @param timestamp Timestamp associated with the update.
    function updateAnswer(int256 answer, uint256 timestamp) external {
        if (answer <= 0) revert InvalidAnswer();

        uint256 appliedTimestamp = timestamp == 0 ? block.timestamp : timestamp;
        uint80 newRoundId = _latestRoundId + 1;
        _rounds[newRoundId] = RoundData({
            answer: answer,
            startedAt: appliedTimestamp,
            updatedAt: appliedTimestamp
        });
        _latestRoundId = newRoundId;

        emit AnswerUpdated(answer, newRoundId, appliedTimestamp);
        emit NewRound(newRoundId, msg.sender, appliedTimestamp);
    }

    // --------------------------------------------------------------------
    // IAggregatorV2V3Interface implementation
    // --------------------------------------------------------------------

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function latestAnswer() external view override returns (int256) {
        return _getRound(_latestRoundId).answer;
    }

    function latestTimestamp() external view override returns (uint256) {
        return _getRound(_latestRoundId).updatedAt;
    }

    function latestRound() external view override returns (uint256) {
        return _latestRoundId;
    }

    function getAnswer(uint256 roundId) external view override returns (int256) {
        return _getRound(uint80(roundId)).answer;
    }

    function getTimestamp(uint256 roundId) external view override returns (uint256) {
        return _getRound(uint80(roundId)).updatedAt;
    }

    function getRoundData(uint80 roundId)
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        RoundData memory round = _getRound(roundId);
        return (roundId, round.answer, round.startedAt, round.updatedAt, roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        uint80 roundId = _latestRoundId;
        RoundData memory round = _getRound(roundId);
        return (roundId, round.answer, round.startedAt, round.updatedAt, roundId);
    }

    // --------------------------------------------------------------------
    // Internal utilities
    // --------------------------------------------------------------------

    function _getRound(uint80 roundId) internal view returns (RoundData memory) {
        RoundData memory round = _rounds[roundId];
        if (round.updatedAt == 0) revert NoDataPresent(roundId);
        return round;
    }
}

