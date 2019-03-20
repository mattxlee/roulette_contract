pragma solidity ^0.5.0;

import "./SafeMath.sol";

//==============================================================================
//  |  _      _ _ | _  .
//  |<(/_\/  (_(_||(_  .
//=======/======================================================================
library KeyCalc {
    using SafeMath for *;
    /**
     * @dev calculates number of keys received given X eth
     * @param _curEth current amount of eth in contract
     * @param _newEth eth being spent
     * @return amount of ticket purchased
     */
    function keysRec(uint256 _curEth, uint256 _newEth)
        internal
        pure
        returns (uint256)
    {
        return(keys((_curEth).add(_newEth)).sub(keys(_curEth)));
    }

    /**
     * @dev calculates amount of eth received if you sold X keys
     * @param _curKeys current amount of keys that exist
     * @param _sellKeys amount of keys you wish to sell
     * @return amount of eth received
     */
    function ethRec(uint256 _curKeys, uint256 _sellKeys)
        internal
        pure
        returns (uint256)
    {
        return((eth(_curKeys)).sub(eth(_curKeys.sub(_sellKeys))));
    }

    /**
     * @dev calculates how many keys would exist with given an amount of eth
     * @param _eth eth "in contract"
     * @return number of keys that would exist
     */
    function keys(uint256 _eth)
        internal
        pure
        returns(uint256)
    {
        return ((((((_eth).mul(1000000000000000000)).mul(312500000000000000000000000)).add(5624988281256103515625000000000000000000000000000000000000000000)).sqrt()).sub(74999921875000000000000000000000)) / (156250000);
    }

    /**
     * @dev calculates how much eth would be in contract given a number of keys
     * @param _keys number of keys "in contract"
     * @return eth that would exists
     */
    function eth(uint256 _keys)
        internal
        pure
        returns(uint256)
    {
        return ((78125000).mul(_keys.sq()).add(((149999843750000).mul(_keys.mul(1000000000000000000))) / (2))) / ((1000000000000000000).sq());
    }

    /**
     * @dev calculates how much profit you make by holding these keys
     * @param _keys number of keys are "holding"
     * @param _profitPerKey the profit of each key currently
     * @return the profit
     */
    function profit(uint256 _keys, uint256 _profitPerKey)
        internal
        pure
        returns(uint256)
    {
        return _keys.mul(_profitPerKey) / 1e18;
    }

    /**
     * @dev calculates the profit per key
     * @param _keys number of keys those you total have
     * @param _eth how much eth in contract
     * @return returns the average value of each key
     */
    function ppk(uint256 _keys, uint256 _eth)
        internal
        pure
        returns(uint256)
    {
        return _eth.mul(1e18) / _keys;
    }
}
