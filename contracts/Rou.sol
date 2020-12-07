// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.5;

import "./SafeMath.sol";

library Rou {
    using SafeMath for uint256;

    uint256 constant ROU = 1e16;

    /**
     * @dev Convert rou to eth
     * @param _rou Value in rou
     * @return Value in eth
     */
    function toEth(uint256 _rou) internal pure returns (uint256) {
        return _rou.mul(ROU);
    }
}
