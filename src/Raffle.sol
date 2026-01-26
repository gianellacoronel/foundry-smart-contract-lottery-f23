// Layout of Contract:
// license
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions


// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
/**
* @title A sample Raffle contract
* @author  Gianella Coronel
* @notice  This contract is for creating a sample raffle
* @dev Implements Chainlink VRFv2.5
*/
contract Raffle is VRFConsumerBaseV2Plus{
    /* Errors */
    // It's good practice to set contract's name as as prefix
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);

    /* Type Declarations */
    /* Enum */
    enum RaffleState {
        OPEN,           // 0
        CALCULATING     // 1
    }

    /* State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    // @dev The duration of the loterry in seconds
    uint256 private immutable i_interval;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    bytes32 private immutable i_keyHash;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /* Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    constructor(uint256 entranceFee, uint256 interval, address vrfCoordinator, bytes32 gasLane, uint256 subscriptionId, uint32 callbackGasLimit)
        VRFConsumerBaseV2Plus(vrfCoordinator){
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN; // = RaffleState(0);
    }

    function enterRaffle() external payable{
        // We comment this because strings are expensive (No gas efficient), so instead we will use Custom Errors
        // require(msg.value >= i_entranceFee, "Not enough ETH sent!");

        // This one works with specific version of Solidity and specific compiler, and it's less efficient gas
        // require(msg.value >= i_entranceFee, SendMoreToEnterRaffle());

        // Error revert called
        // It's more efficient gas
        if (msg.value < i_entranceFee){
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN){
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));

        /*
        Reasons to use EVENTS
        1. Makes migration easier
        2. Makes front end "indexing" easier
        */
        emit RaffleEntered(msg.sender);
    }

    // When should the winner be picked?
    /**
    * @dev This is the function that the Chainlink nodes will call to see if the lottery is ready to have a winner picked.
    * The following should be true in oreder for upkeepNeeded to be true:
    * 1. The time interval has passed between raffle runs
    * 2. The lottery is open
    * 3. The contract has ETH (has players)
    * 4. Implicitly, your subscription has LINK
    * @param - ignored
    * @return upkeepNeeded - true if it's time to restart the lottery
    * @return - ignored
    */
    function checkUpkeep(bytes memory /*checkData*/)public view returns(bool upkeepNeeded, bytes memory /* performData */){
        // 1.
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        //2.
        bool hasBalance = address(this).balance > 0;
        bool hasPLayers = s_players.length > 0;

        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPLayers;
        return (upkeepNeeded, hex"");
    }

    /*
    1. Get a random number
    2. Use random number to pick a player
    3. Be automatically called
    */
    function performUpkeep(bytes calldata /* performData */) external {
        // check to see if enough time has passed
        // 1000 - 900 = 100, 50
        (bool upkeepNeeded, ) = checkUpkeep("");
        if(!upkeepNeeded){
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;

        // Get our random number
        // 1. Request RNG (Random Number Generator)
        // 2. Get RNG
        s_vrfCoordinator.requestRandomWords(
          VRFV2PlusClient.RandomWordsRequest({
                    keyHash: i_keyHash,
                    subId: i_subscriptionId,
                    requestConfirmations: REQUEST_CONFIRMATIONS,
                    callbackGasLimit: i_callbackGasLimit,
                    numWords: NUM_WORDS,
                    extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
    }

    // CEI: Checks, Effects, Interactions Pattern
    function fulfillRandomWords(uint256 /* requestId */, uint256[] calldata randomWords) internal override {
        /* Checks */
        // require(...)
        // conditionals



        // s_player = 10
        // random_number = 12
        // 12 % 10 = 2 <- s_players[2] winner

        /* Effect (Internal Contract State) */
        // Using module operator (%), we can get a number between 0 and 9
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0); // reset s_players to an empty array
        s_lastTimeStamp = block.timestamp; // restart lastTimeStamp
        emit WinnerPicked(s_recentWinner);

        /* Interactions (External Contract Interactions) */
        // Method to pay winner
        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if(!success){
            revert Raffle__TransferFailed();
        }
    }

    /* Getter Functions */
    function getEntranceFee() external view returns(uint256){
        return i_entranceFee;
    }

    function getRaffleState() external view returns(RaffleState){
        return s_raffleState;
    }
}
