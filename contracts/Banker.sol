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

/// Main contract
contract Banker {
    using SafeMath for uint256;

    struct Game {
        uint256 poolEth; // Will be added from last game
        uint256 jackpotEth; // Each jackpot will drain all
    }

    mapping (uint256 => Game) games;
    uint256 gameID;

    struct Player {
        address payable addr;
        bytes32 name;
        uint256 affID;
        uint256 deadEth;
        uint256 keys;
    }

    // Player
    mapping (uint256 => Player) players;
    mapping (bytes32 => uint256) name2plyID;
    mapping (address => uint256) addr2plyID;
    uint256 lastPlyID;

    // This struct will store bet related values
    struct Bet {
        address payable player;
        uint256 transferredAmount; // For refund.
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

    // 0~maxBetWei is the range for the amount of placed bet.
    uint256 public maxBetWei;

    // odds for roulette game
    mapping (uint256 => uint256) odds;

    // All bets store in this map
    mapping (uint256 => Bet) bets;

    /**
     * @dev Emit on a new bet is placed
     * @param transferredAmount Represent how many eth are transferred
     * @param magicNumber The hash value of the random number
     * @param betData Bet details
     * @param lastRevealBlock The bet should be revealed before this block or the bet will never be revealed
     */
    event BetIsPlaced(
        uint256 transferredAmount,
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
     * @param winAmount The amount of the contract has paid to player.
     */
    event BetIsRevealed(uint256 magicNumber, uint256 dice, uint256 winAmount);

    // Ensure the function is called by owner
    modifier ownerOnly() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    /**
     * @dev Constructor will initialize owner, maxBetWei and odds
     */
    constructor() public {
        owner = msg.sender;

        gameID = 1;
        lastPlyID = 1;

        maxBetWei = eth1 / 10;

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
     * @dev Withdraw eth to owner account
     * @param _wei The amount of eth to withdraw
     */
    function withdrawToOwner(uint256 _wei) public ownerOnly {
        require(
            address(this).balance >= _wei,
            "The value of this withdrawal is invalid."
        );

        owner.transfer(_wei);
    }

    /**
     * @dev If the player has enough keys then he is able to buy a name. (Only 1 name for each player)
     * @param _name A new player name to buy.
     */
    function buyName(bytes32 _name) public {
        address _plyAddr = msg.sender;

        uint256 _plyID = addr2ply[_plyAddr];
        require(_plyID != 0, "Player doesn't exist!");

        Player storage _player = players[_plyID];
        require(_player.name != 0, "You already have a name!");

        require(_player.keys > 100, "Not enough keys to buy a name!");
        require(name2plyID[_name] == 0, "The name does already exist!");

        _player.name = _name;
        name2plyID[_name] = _plyID;
    }

    /**
     * @dev Return the name of player with given address
     * @return The name of the player
     */
    function getName(address _plyAddr) public view returns (bytes32) {
        uint256 _plyID = addr2plyID;
        require(_plyID > 0, "Player doesn't exist!");

        return players[_plyID].name;
    }

    /**
     * @dev Set the value of max bet wei
     * @param _numOfWei How many you want to set as the max bet wei
     */
    function setMaxBetWei(uint256 _numOfWei) public ownerOnly {
        require(_numOfWei <= eth1.mul(10) && _numOfWei >= 1e18 / 100, "The amount of max bet is out of range!");
        maxBetWei = _numOfWei;
    }

    /**
     * @dev This function will convert the amount of chips to eth value
     * @param _amount The amount of chips
     * @return The value of eth
     */
    function convertAmountToWei(uint256 _amount) private pure returns (uint256) {
        return _amount.mul(rou1);
    }

    /**
     * @dev Calculate how many amount of chips from bet details
     * @param _betData The data of bet details
     * @return Total amount value are calculated
     */
    function calcBetAmount(bytes32 _betData) private pure returns (uint256) {
        uint256 _numOfBets = uint8(_betData[0]);
        require(_numOfBets > 0 && _numOfBets <= 15, "Invalid number value of bets.");

        uint256 _p = 1;
        uint256 _betAmount = 0;

        for (uint256 _dataIndex = 0; _dataIndex < _numOfBets; ++_dataIndex) {
            uint256 _amount = uint8(_betData[_p++]);
            require(
                _amount == 100 || _amount == 50 || _amount == 20 || _amount == 10 ||
                    _amount == 5 || _amount == 2 || _amount == 1,
                "Invalid bet amount."
            );

            _betAmount = _betAmount.add(_amount);

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

        return _betAmount;
    }

    /**
     * @dev Calculate the amount to win according to the result
     * @param _betData The bet details
     * @param _dice The result
     * @return Amount of chips should win
     */
    function calcWinAmountOnNumber(bytes32 _betData, uint256 _dice) private view returns (uint256) {
        uint8 _numOfBets = uint8(_betData[0]);
        require(_numOfBets <= 15, "Too many bets.");

        // Reading index of betData.
        uint256 _pData = 1;
        uint256 _winAmount = 0;

        // Loop every bet.
        for (uint256 _betIndex = 0; _betIndex < _numOfBets; ++_betIndex) {
            require(_pData < 32, "Out of betData's range.");

            // Now read the bet amount (in ROU).
            uint256 _amount = uint8(_betData[_pData++]);
            require(
                _amount == 100 || _amount == 50 || _amount == 20 || _amount == 10 ||
                    _amount == 5 || _amount == 2 || _amount == 1,
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
                        _winAmount = _winAmount.add((odds[_numOfNumsOrIndex] + 1).mul(_amount));
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
                    _winAmount = _winAmount.add((odds[_numOfNums] + 1).mul(_amount));
                }
            }
        }

        return _winAmount;
    }

    /**
     * @dev Calculate the amount we will win max
     * @param _betData The bet details
     * @return The max amount of chips we will win
     */
    function calcMaxWinAmount(bytes32 _betData) private view returns (uint256) {
        uint256 _maxWinAmount = 0;
        for (uint256 _guessWinNumber = 0; _guessWinNumber <= 37; ++_guessWinNumber) {
            uint256 _amount = calcWinAmountOnNumber(_betData, _guessWinNumber);
            if (_amount > _maxWinAmount) {
                _maxWinAmount = _amount;
            }
        }
        return _maxWinAmount;
    }

    /**
     * @dev Erase bet information on specified magic number
     * @param _magicNumber The hash value and it is also the place where the bet info. are stored
     */
    function clearBet(uint256 _magicNumber) private {
        Bet storage _bet = bets[_magicNumber];
        _bet.player = address(0);
        _bet.transferredAmount = 0;
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

        // Throw if there are not enough wei are provided by customer.
        uint256 _betAmount = calcBetAmount(_betData);
        uint256 _betWei = convertAmountToWei(_betAmount);
        uint256 _wei = msg.value;

        require(_wei >= _betWei, "There are not enough wei are provided by customer.");
        require(_betWei <= maxBetWei, "Exceed the maximum.");

        // Check the signature.
        bytes memory _prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 _hashValue = keccak256(abi.encodePacked(_magicNumber, _lastRevealBlock));
        address _signer = ecrecover(keccak256(abi.encodePacked(_prefix, _hashValue)), 28, _signR, _signS);
        require(_signer == banker, "The signature is not signed by the banker.");

        // Prepare and save bet record.
        _bet.player = msg.sender;
        _bet.transferredAmount = _wei;
        _bet.betData = _betData;
        _bet.placedOnBlock = _currBlock;
        _bet.lastRevealBlock = _lastRevealBlock;
        bets[_magicNumber] = _bet;

        emit BetIsPlaced(_wei, _magicNumber, _betData, _lastRevealBlock);
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
        address payable _betPlayer = _bet.player;
        uint256 _betPlacedOnBlock = _bet.placedOnBlock;
        uint256 _currBlock = block.number;

        require(
            _betPlayer != address(0),
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
        uint256 _winAmount = calcWinAmountOnNumber(_bet.betData, _dice);
        uint256 _winWei = 0;
        if (_winAmount > 0) {
            _winWei = convertAmountToWei(_winAmount);
            if (address(this).balance < _winWei) {
                emit BetCannotBeRevealed(_magicNumber, RevealFailStatus.InsufficientContractBalance);
                return;
            }
            _betPlayer.transfer(_winWei);
        }
        emit BetIsRevealed(_magicNumber, _dice, _winAmount);
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

        _playerAddr.transfer(_bet.transferredAmount);

        // Clear the slot.
        clearBet(_magicNumber);
    }
}
