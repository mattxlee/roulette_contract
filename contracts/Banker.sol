//      ___________                          ______    __________
// _______  /___  /_______________________  ____  /______  /__  /_____
// _  _ \  __/_  __ \  _ \_  ___/  __ \  / / /_  /_  _ \  __/  __/  _ \
// /  __/ /_ _  / / /  __/  /   / /_/ / /_/ /_  / /  __/ /_ / /_ /  __/
// \___/\__/ /_/ /_/\___//_/    \____/\__,_/ /_/  \___/\__/ \__/ \___/
//
// This contract is deployed to https://etheroulette.win
//

pragma solidity ^0.5.0;

import "./SafeMath.sol";
import "./Rou.sol";
import "./KeyCalc.sol";

//==_===================================================================================================================
// |_) _.._ |  _ ._
// |_)(_|| ||<(/_|
//======================================================================================================================
contract Banker {
    using SafeMath for uint256;
    using Rou for uint256;
    using KeyCalc for uint256;

    struct Player {
        address payable addr;
        uint256 affID;
        uint256 deadEth;

        // How many games the player involved
        uint256 firstGID;
        mapping (uint256 => uint256) nextGID;
    }

    struct Wallet {
        uint256 keys;
    }

    // Player
    mapping (uint256 => Player) players;
    mapping (address => uint256) addr2plyID;
    uint256 lastPlyID;

    struct Game {
        uint256 poolEth; // Will be added from last game
        uint256 jackpotEth; // Each jackpot will drain all
        uint256 keys; // Total keys are sold
        mapping (uint256 => Wallet) wallets; // Player wallets (plyID as index)
    }

    mapping (uint256 => Game) games;
    uint256 gameID;

    // This struct will store bet related values
    struct Bet {
        address payable player;
        uint256 betEth;
        bytes32 betData;
        uint256 placedOnBlock;
        uint256 lastRevealBlock;
    }

    // Error declaration
    enum RevealFailStatus { InsufficientContractBalance }

    uint256 constant private eth1 = 1e18;
    uint256 constant private rou1 = 1e16;

    // Owner will be able to withdraw and setup a new banker account
    address payable public owner;

    // Banker is the account to generate random number, so it is the key account to verify the signature
    address public banker;

    // maxBetEth is the range for the amount of placed bet.
    uint256 public maxBetEth;

    // odds for roulette game
    mapping (uint256 => uint256) odds;

    // All bets store in this map
    mapping (uint256 => Bet) bets;

    /**
     * @dev Emit on a new bet is placed
     * @param betEth The amount of eth
     * @param magicNumber The hash value of the random number
     * @param betData Bet details
     * @param lastRevealBlock The bet should be revealed before this block or the bet will never be revealed
     */
    event BetIsPlaced(
        uint256 betEth,
        uint256 magicNumber,
        bytes32 betData,
        uint256 lastRevealBlock
    );

    /**
     * @dev Emit on a bet is not able to reveal
     * @param magicNumber The hash value of the random number
     * @param reason The fail reason
     */
    event BetCannotBeRevealed(uint256 magicNumber, RevealFailStatus reason);

    /**
     * @dev Emit on a bet is revealed
     * @param magicNumber The hash value of the random number
     * @param dice The result number has been revealed eventually
     * @param winAmount The amount of the contract has paid to player
     */
    event BetIsRevealed(uint256 magicNumber, uint256 dice, uint256 winAmount);

    /**
     * @dev Emit on current jackpot is revealed
     * @param winnerAddr Address of the winner
     * @param eth The amount of the reward in eth
     */
    event JackpotIsRevealed(address winnerAddr, uint256 eth);

    // Ensure the function is called by owner
    modifier ownerOnly() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

//==_===================================================================================================================
// |_)._o   _._|_ _  ._ _  __|_|_  _  _| _
// |  | |\/(_| |_(/_ | | |(/_|_| |(_)(_|_>

    /**
     * @dev Register an address as a player, if the player already exists, then returns the existing ID
     * @param _plyAddr Address of the player
     * @return The player ID which is registered from our storage
     */
    function registerPlayer(address _plyAddr) private returns (uint256) {
        // We should ensure the player is registered
        uint256 _plyID = addr2plyID[_plyAddr];
        if (_plyID == 0) {
            addr2plyID[_plyAddr] = lastPlyID;
            ++lastPlyID;
        }
        return _plyID;
    }

    /**
     * @dev Core function for a player buy keys
     * @param _plyID Player ID
     * @param _eth Amount of eth the player will spend
     */
    function buyKeys(uint256 _plyID, uint256 _eth) private {
        Game storage _game = games[gameID];
        Wallet storage _wallet = _game.wallets[_plyID];

        uint256 _ethOfKeys = _game.keys.eth();
        uint256 _newKeys = _ethOfKeys.keysRec(_eth);

        uint256 _ppk = 0;
        if (_game.keys > 0) {
            _ppk = _game.keys.ppk(_game.poolEth);
        }

        Player storage _player = players[_plyID];
        _player.deadEth = _player.deadEth.add(_newKeys.profit(_ppk));

        _game.keys = _game.keys.add(_newKeys);
        _wallet.keys = _wallet.keys.add(_newKeys);

        // Game ID list adjustment
        uint256 _GID = _player.firstGID;
        uint256 _lastGID = 0;
        while (_GID > 0) {
            if (_GID == gameID) {
                // The game ID is already exist from the list
                return;
            }
            _lastGID = _GID;
            _GID = _player.nextGID[_GID];
        }
        if (_lastGID == 0) {
            _player.firstGID = gameID;
        } else {
            _player.nextGID[_lastGID] = gameID;
        }
    }

    /**
     * @dev Distribute dividends to the player and affiliate if he/she exists, also will adjust the pool and jackpot
     * @param _eth How much eth to buy keys
     * @param _plyAddr Address of the player
     */
    function distributeDividends(uint256 _eth, address _plyAddr) private {
        uint256 _plyID = addr2plyID[_plyAddr];

        buyKeys(_plyID, _eth.mul(90) / 100);
        Player storage _player = players[_plyID];
        if (_player.affID > 0) {
            buyKeys(_plyID, _eth.mul(2) / 100);
            buyKeys(_player.affID, _eth.mul(8) / 100);
        }

        Game storage _game = games[gameID];
        uint256 _inc = _eth / 38 / 2;
        _game.poolEth = _game.poolEth.add(_inc);
        _game.jackpotEth = _game.jackpotEth.add(_inc);
    }

//==_===================================================================================================================
// |_) |_ |o _ ._ _  __|_|_  _  _| _
// ||_||_)||(_ | | |(/_|_| |(_)(_|_>

    /**
     * @dev Constructor will initialize owner, maxBetEth and odds
     */
    constructor() public {
        owner = msg.sender;

        gameID = 1;
        lastPlyID = 1;

        maxBetEth = eth1 / 10;

        // Initialize odds.
        odds[1] = 35;
        odds[2] = 17;
        odds[3] = 11;
        odds[4] = 8;
        odds[5] = 6;
        odds[6] = 5;
        odds[12] = 2;
        odds[18] = 1;
    }

    /**
     * @dev Assign a new banker account to contract
     * @param _newBanker Address of the new banker account
     */
    function setBanker(address _newBanker) public ownerOnly {
        banker = _newBanker;
    }

    /**
     * @dev Deposit eth to contract
     */
    function deposit() public payable {}

    /**
     * @dev Set the value of max bet eth
     * @param _numOfEth How many you want to set as the max bet eth
     */
    function setMaxBetEth(uint256 _numOfEth) public ownerOnly {
        require(_numOfEth <= eth1.mul(10) && _numOfEth >= 1e18 / 100, "The amount of max bet is out of range!");
        maxBetEth = _numOfEth;
    }

    /**
     * @dev Calculate how many amount of chips from bet details
     * @param _betData The data of bet details
     * @return Total amount value are calculated
     */
    function calcBetRou(bytes32 _betData) private pure returns (uint256) {
        uint256 _numOfBets = uint8(_betData[0]);
        require(_numOfBets > 0 && _numOfBets <= 15, "Invalid number value of bets.");

        uint256 _p = 1;
        uint256 _betRou = 0;

        for (uint256 _dataIndex = 0; _dataIndex < _numOfBets; ++_dataIndex) {
            uint256 _rou = uint8(_betData[_p++]);
            require(
                _rou == 100 || _rou == 50 || _rou == 20 || _rou == 10 ||
                    _rou == 5 || _rou == 2 || _rou == 1,
                "Invalid bet rou."
            );

            _betRou = _betRou.add(_rou);

            // Skip numbers.
            uint256 _numOfNumsOrIndex = uint8(_betData[_p++]);
            if (_numOfNumsOrIndex <= 4) {
                _p = _p.add(_numOfNumsOrIndex);
            } else {
                require(_numOfNumsOrIndex >= 129 && _numOfNumsOrIndex <= 152, "Invalid bet index.");
            }

            // Note: When _numOfNumsOrIndex > 4 (Actually it should be larger than 128),
            //       there is no number follows. So we do not skip any byte in this case.
        }

        return _betRou;
    }

    /**
     * @dev Calculate the amount to win according to the result
     * @param _betData The bet details
     * @param _dice The result
     * @return Amount of chips should win
     */
    function calcWinRouOnNumber(bytes32 _betData, uint256 _dice) private view returns (uint256) {
        uint8 _numOfBets = uint8(_betData[0]);
        require(_numOfBets <= 15, "Too many bets.");

        // Reading index of betData.
        uint256 _pData = 1;
        uint256 _winRou = 0;

        // Loop every bet.
        for (uint256 _betIndex = 0; _betIndex < _numOfBets; ++_betIndex) {
            require(_pData < 32, "Out of betData's range.");

            // Now read the bet amount (in ROU).
            uint256 _rou = uint8(_betData[_pData++]);
            require(
                _rou == 100 || _rou == 50 || _rou == 20 || _rou == 10 ||
                    _rou == 5 || _rou == 2 || _rou == 1,
                "Invalid bet amount."
            );

            // The number of numbers to bet.
            uint256 _numOfNumsOrIndex = uint8(_betData[_pData++]);

            // Read and check numbers.
            if (_numOfNumsOrIndex <= 4) {
                // We will read numbers from the following bytes.
                bool _hit = false;
                for (uint256 _numIndex = 0; _numIndex < _numOfNumsOrIndex; ++_numIndex) {
                    require(_pData < 32, "Out of betData's range.");

                    uint256 _number = uint8(_betData[_pData++]);
                    require(_number >= 0 && _number <= 37, "Invalid bet number.");

                    if (!_hit && _number == _dice) {
                        _hit = true;
                        // Increase win amount.
                        _winRou = _winRou.add((odds[_numOfNumsOrIndex] + 1).mul(_rou));
                    }
                }
            } else {
                // This is the index from table.
                require(_numOfNumsOrIndex >= 129 && _numOfNumsOrIndex <= 152, "Bad bet index.");

                uint256 _numOfNums = 0;

                if (_numOfNumsOrIndex == 129 && (_dice >= 1 && _dice <= 6)) {
                    _numOfNums = 6;
                }

                if (_numOfNumsOrIndex == 130 && (_dice >= 4 && _dice <= 9)) {
                    _numOfNums = 6;
                }

                if (_numOfNumsOrIndex == 131 && (_dice >= 7 && _dice <= 12)) {
                    _numOfNums = 6;
                }

                if (_numOfNumsOrIndex == 132 && (_dice >= 10 && _dice <= 15)) {
                    _numOfNums = 6;
                }

                if (_numOfNumsOrIndex == 133 && (_dice >= 13 && _dice <= 18)) {
                    _numOfNums = 6;
                }

                if (_numOfNumsOrIndex == 134 && (_dice >= 16 && _dice <= 21)) {
                    _numOfNums = 6;
                }

                if (_numOfNumsOrIndex == 135 && (_dice >= 19 && _dice <= 24)) {
                    _numOfNums = 6;
                }

                if (_numOfNumsOrIndex == 136 && (_dice >= 22 && _dice <= 27)) {
                    _numOfNums = 6;
                }

                if (_numOfNumsOrIndex == 137 && (_dice >= 25 && _dice <= 30)) {
                    _numOfNums = 6;
                }

                if (_numOfNumsOrIndex == 138 && (_dice >= 28 && _dice <= 33)) {
                    _numOfNums = 6;
                }

                if (_numOfNumsOrIndex == 139 && (_dice >= 31 && _dice <= 36)) {
                    _numOfNums = 6;
                }

                if (_numOfNumsOrIndex == 140 && ((_dice >= 0 && _dice <= 3) || _dice == 37)) {
                    _numOfNums = 5;
                }

                uint256 _number;

                if (_numOfNumsOrIndex == 141) {
                    for (_number = 1; _number <= 34; _number += 3) {
                        if (_number == _dice) {
                            _numOfNums = 12;
                            break;
                        }
                    }
                }

                if (_numOfNumsOrIndex == 142) {
                    for (_number = 2; _number <= 35; _number += 3) {
                        if (_number == _dice) {
                            _numOfNums = 12;
                            break;
                        }
                    }
                }

                if (_numOfNumsOrIndex == 143) {
                    for (_number = 3; _number <= 36; _number += 3) {
                        if (_number == _dice) {
                            _numOfNums = 12;
                            break;
                        }
                    }
                }

                if (_numOfNumsOrIndex == 144 && (_dice >= 1 && _dice <= 12)) {
                    _numOfNums = 12;
                }

                if (_numOfNumsOrIndex == 145 && (_dice >= 13 && _dice <= 24)) {
                    _numOfNums = 12;
                }

                if (_numOfNumsOrIndex == 146 && (_dice >= 25 && _dice <= 36)) {
                    _numOfNums = 12;
                }

                if (_numOfNumsOrIndex == 147) {
                    for (_number = 1; _number <= 35; _number += 2) {
                        if (_number == _dice) {
                            _numOfNums = 18;
                            break;
                        }
                    }
                }

                if (_numOfNumsOrIndex == 148) {
                    for (_number = 2; _number <= 36; _number += 2) {
                        if (_number == _dice) {
                            _numOfNums = 18;
                            break;
                        }
                    }
                }

                if (_numOfNumsOrIndex == 149 &&
                    (_dice == 1 || _dice == 3 || _dice == 5 || _dice == 7 || _dice == 9 || _dice == 12 ||
                    _dice == 14 || _dice == 16 || _dice == 18 || _dice == 19 || _dice == 21 || _dice == 23 ||
                    _dice == 25 || _dice == 27 || _dice == 30 || _dice == 32 || _dice == 34 || _dice == 36)) {
                    _numOfNums = 18;
                }

                if (_numOfNumsOrIndex == 150 &&
                    (_dice == 2 || _dice == 4 || _dice == 6 || _dice == 8 || _dice == 10 || _dice == 11 ||
                    _dice == 13 || _dice == 15 || _dice == 17 || _dice == 20 || _dice == 22 || _dice == 24 ||
                    _dice == 26 || _dice == 28 || _dice == 29 || _dice == 31 || _dice == 33 || _dice == 35)) {
                    _numOfNums = 18;
                }

                if (_numOfNumsOrIndex == 151 && (_dice >= 1 && _dice <= 18)) {
                    _numOfNums = 18;
                }

                if (_numOfNumsOrIndex == 152 && (_dice >= 19 && _dice <= 36)) {
                    _numOfNums = 18;
                }

                if (_numOfNums > 0) {
                    _winRou = _winRou.add((odds[_numOfNums] + 1).mul(_rou));
                }
            }
        }

        return _winRou;
    }

    /**
     * @dev Calculate the amount we will win max
     * @param _betData The bet details
     * @return The max amount of chips we will win
     */
    function calcMaxWinRou(bytes32 _betData) private view returns (uint256) {
        uint256 _maxWinRou = 0;
        for (uint256 _guessWinNumber = 0; _guessWinNumber <= 37; ++_guessWinNumber) {
            uint256 _rou = calcWinRouOnNumber(_betData, _guessWinNumber);
            if (_rou > _maxWinRou) {
                _maxWinRou = _rou;
            }
        }
        return _maxWinRou;
    }

    /**
     * @dev Erase bet information on specified magic number
     * @param _magicNumber The hash value and it is also the place where the bet info. are stored
     */
    function clearBet(uint256 _magicNumber) private {
        Bet storage _bet = bets[_magicNumber];
        _bet.player = address(0);
        _bet.betEth = 0;
        _bet.betData = bytes32(0);
        _bet.placedOnBlock = 0;
        _bet.lastRevealBlock = 0;
    }

    /**
     * @dev Place a bet
     * @param _magicNumber The hash value of the random number that is provided by our server
     * @param _lastRevealBlock The bet should be revealed before this block number,
     *                         otherwise the bet will never be revealed
     * @param _betData The bet details
     * @param _signR The signature R value
     * @param _signS The signature S value
     */
    function placeBet(
        uint256 _magicNumber,
        uint256 _lastRevealBlock,
        bytes32 _betData,
        bytes32 _signR,
        bytes32 _signS
    )
        public
        payable
    {
        uint256 _currBlock = block.number;
        require(
            _currBlock <= _lastRevealBlock,
            "Timeout of current bet to place."
        );

        // Check the slot and make sure there is no playing bet.
        Bet storage _bet = bets[_magicNumber];
        require(_bet.player == address(0), "The slot is not empty.");

        // Throw if there are not enough eth are provided by customer.
        uint256 _betRou = calcBetRou(_betData);
        uint256 _betEth = _betRou.toEth();
        uint256 _eth = msg.value;

        require(_eth >= _betEth, "There are not enough eth are provided by customer.");
        require(_betEth <= maxBetEth, "Exceed the maximum.");

        // Check the signature.
        bytes memory _prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 _hashValue = keccak256(abi.encodePacked(_magicNumber, _lastRevealBlock));
        address _signer = ecrecover(keccak256(abi.encodePacked(_prefix, _hashValue)), 28, _signR, _signS);
        require(_signer == banker, "The signature is not signed by the banker.");

        // Prepare and save bet record.
        _bet.player = msg.sender;
        _bet.betEth = _betEth;
        _bet.betData = _betData;
        _bet.placedOnBlock = _currBlock;
        _bet.lastRevealBlock = _lastRevealBlock;
        bets[_magicNumber] = _bet;
        registerPlayer(_bet.player);

        emit BetIsPlaced(_eth, _magicNumber, _betData, _lastRevealBlock);
    }

    /**
     * @dev Reveal a bet to calculate the result
     * @param _randomNumber The random number
     */
    function revealBet(uint256 _randomNumber) public {
        // Get the magic-number and find the slot of the bet.
        uint256 _magicNumber = uint256(
            keccak256(abi.encodePacked(_randomNumber))
        );
        Bet storage _bet = bets[_magicNumber];

        // Save to local variables.
        address payable _plyAddr = _bet.player;
        uint256 _betPlacedOnBlock = _bet.placedOnBlock;
        uint256 _currBlock = block.number;

        require(
            _plyAddr != address(0),
            "The bet slot cannot be empty."
        );

        require(
            _betPlacedOnBlock < _currBlock,
            "Cannot reveal the bet on the same block where it was placed."
        );

        require(
            _currBlock <= _bet.lastRevealBlock,
            "The bet is out of the block range (Timeout!)."
        );

        // Calculate the result.
        bytes32 _betHash = keccak256(abi.encodePacked(_randomNumber, blockhash(_betPlacedOnBlock)));
        uint256 _dice = uint256(_betHash) % 38;

        // Calculate win amount.
        uint256 _winRou = calcWinRouOnNumber(_bet.betData, _dice);
        uint256 _winEth = 0;

        if (_winRou > 0) {
            _winEth = _winRou.toEth();
            if (address(this).balance < _winEth) {
                emit BetCannotBeRevealed(_magicNumber, RevealFailStatus.InsufficientContractBalance);
                return;
            }
            _plyAddr.transfer(_winEth);
        }
        emit BetIsRevealed(_magicNumber, _dice, _winRou);

        // Calculate how many eth remains to buy keys
        if (_bet.betEth > _winEth) {
            // (1/38) * 90% of lose eth will be used to buy keys
            uint256 _loseEth = _bet.betEth.sub(_winEth);
            distributeDividends(_loseEth, _plyAddr);

            // Jackpot should be revealed here, we use _betHash to decide with 0.1% chance
            uint256 _jackpotHit = uint256(_betHash) % 1000;
            if (_jackpotHit == 888) {
                // Jackpot hit, 10% are saved for next round
                Game storage _game = games[gameID];
                uint256 _jackpotEth = _game.jackpotEth.mul(90) / 100;
                _plyAddr.transfer(_jackpotEth);
                emit JackpotIsRevealed(_plyAddr, _jackpotEth);

                // Calculate how many eth are remain
                uint256 _jackpotEthRemains = _game.jackpotEth.sub(_jackpotEth);

                // We start a new game here
                ++gameID;
                _game = games[gameID];
                _game.jackpotEth = _jackpotEthRemains;
            }
        }

        clearBet(_magicNumber);
    }

    /**
     * @dev Refund bet amount back to player and clear the bet
     * @param _magicNumber The hash value of the random number
     */
    function refundBet(uint256 _magicNumber) public {
        Bet storage _bet = bets[_magicNumber];
        address payable _playerAddr = _bet.player;

        require(_playerAddr != address(0), "The bet slot is empty.");
        require(block.number > _bet.lastRevealBlock, "The bet is still in play.");

        _playerAddr.transfer(_bet.betEth);

        // Clear the slot.
        clearBet(_magicNumber);
    }

    /**
     * @dev Query how many eth remains from the player
     * @param _plyAddr Address of the player
     * @return Eth left
     */
    function getPlayerEth(address _plyAddr) public view returns (uint256) {
        uint256 _plyID = addr2plyID[_plyAddr];
        require(_plyID > 0, "It is not our player yet!");

        Player storage _player = players[_plyID];
        uint256 _GID = _player.firstGID;
        uint256 _eth;

        while (_GID > 0) {
            Game storage _game = games[_GID];
            uint256 _keys = _game.wallets[_plyID].keys;
            if (_keys > 0) {
                uint256 _ppk = _game.keys.ppk(_game.poolEth);
                _eth = _eth.add(_keys.profit(_ppk));
            }
            _GID = _player.nextGID[_GID];
        }

        _eth = _eth.sub(_player.deadEth);
        return _eth;
    }

    /**
     * @dev Query how many keys from the player of current game
     * @param _plyAddr Address of the player
     * @return Keys
     */
    function getPlayerKeysOnCurrGame(address _plyAddr) public view returns (uint256) {
        uint256 _plyID = addr2plyID[_plyAddr];
        require(_plyID > 0, "It is not our player yet!");

        Wallet storage _wallet = games[gameID].wallets[_plyID];
        return _wallet.keys;
    }

    /**
     * @dev Return affiliate ID of the player
     * @param _plyAddr Address of the player
     * @return Affiliate ID or 0 means the player has no affiliate
     */
    function getPlayerAffID(address _plyAddr) public view returns (uint256) {
        uint256 _plyID = addr2plyID[_plyAddr];
        require(_plyID > 0, "It is not our player yet!");

        return players[_plyID].affID;
    }

    /**
     * @dev Get contract balance
     * @return Balance value in eth
     */
    function getBalance() public view returns (uint256) {
        uint256 _eth = address(this).balance;

        for (uint256 _GID = 1; _GID <= gameID; ++_GID) {
            Game storage _game = games[_GID];
            if (_eth <= _game.poolEth) {
                // Now I have debt, sigh!
                return 0;
            }
            _eth = _eth.sub(games[_GID].poolEth);
        }
        return _eth;
    }

    /**
     * @dev Returns the balance of current jackpot
     * @return Balance in eth
     */
    function getJackpotBalance() public view returns (uint256) {
        Game storage _game = games[gameID];
        return _game.jackpotEth;
    }

    /**
     * @dev Withdraw eth
     * @param _eth Amount of eth to withdraw
     */
    function withdraw(uint256 _eth) public {
        address payable _addr = msg.sender;
        if (_addr == owner) {
            // Owner withdrawal
            uint256 _ethLeft = getBalance();
            require(_eth <= _ethLeft, "Not enough eth to withdraw to owner!");
            _addr.transfer(_eth);
        } else {
            // Player or affiliate withdrawal
            uint256 _plyID = addr2plyID[_addr];
            require(_plyID > 0, "You are not a player!");

            uint256 _ethLeft = getPlayerEth(_addr);
            require(_eth <= _ethLeft, "Not enough eth to withdraw to player!");
            _addr.transfer(_eth);

            Player storage _player = players[_plyID];
            _player.deadEth = _player.deadEth.add(_eth);
        }
    }
}
