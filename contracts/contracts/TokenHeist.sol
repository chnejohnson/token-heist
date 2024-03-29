// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "poseidon-solidity/PoseidonT6.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol";

// import "hardhat/console.sol";

interface IVerifier {
    function verifyProof(
        uint256[2] calldata _pA,
        uint256[2][2] calldata _pB,
        uint256[2] calldata _pC,
        uint256[13] calldata _pubSignals
    ) external view returns (bool);
}

contract TokenHeist is ERC2771Context {
    uint8 public constant MAX_COPS = 5;

    enum Role {
        None,
        Thief,
        Police
    }

    Role public currentRole;

    enum GameState {
        NotStarted,
        RoundOneInProgress,
        RoundTwoInProgress,
        Ended
    }

    GameState public gameState = GameState.NotStarted;

    uint256[2] public scores; // [player1 score, player2 score]

    IVerifier public immutable sneakVerifier;
    uint256[9] public prizeMap;
    uint256 timeLimitPerTurn;
    uint256 timeUpPoints;

    constructor(
        IVerifier _sneakVerifier,
        ERC2771Forwarder _forwarder,
        uint256[9] memory _prizeMap,
        uint256 _timeLimitPerTurn,
        uint256 _timeUpPoints
    ) ERC2771Context(address(_forwarder)) {
        sneakVerifier = _sneakVerifier;
        prizeMap = _prizeMap;
        timeLimitPerTurn = _timeLimitPerTurn;
        timeUpPoints = _timeUpPoints;

        // verify linked poseidon library
        if (hashCommitment([int8(1), int8(1), int8(1), int8(1), int8(1)]) == 0) revert PoseidonT6NotLinked();
    }

    address public player1;
    address public player2;
    mapping(Role => address) public roles;

    // Thief
    uint256 public commitment;
    uint256 public thiefTime;

    // Police
    int8[2][5] public ambushes = [[-1, -1], [-1, -1], [-1, -1], [-1, -1], [-1, -1]]; // why it's [2][5] instead of [5][2]?
    uint8 public copUsedCount = 0;
    uint256 public policeTime;

    // ================================ Events ================================

    event Registered(address indexed player);
    event CancelledRegistration(address indexed player);
    event GameStarted(address indexed player1, address indexed player2);
    event GameEnded(address indexed winner, uint256[2] scores);
    event Sneak(GameState gameState, address indexed player, bool noticed);
    event Reveal(bool caught, address indexed player, int8[5] flattenedSneakPaths);
    event Dispatch(GameState gameState, address indexed player);
    event TimeUp(GameState gameState, Role role, address indexed player);

    // ================================ Functions ================================

    function reset() public gameEnded {
        gameState = GameState.NotStarted;
        currentRole = Role.None;
        player1 = address(0);
        player2 = address(0);
        roles[Role.Thief] = address(0);
        roles[Role.Police] = address(0);
        scores = [0, 0];
        commitment = 0;
        thiefTime = 0;
        copUsedCount = 0;
        policeTime = 0;
        for (uint8 i = 0; i < MAX_COPS; i++) {
            ambushes[i] = [-1, -1];
        }
    }

    /**
     * @dev Start the game if both players have registered.
     */
    function register(uint8 n) public gameNotStarted {
        require(n == 1 || n == 2, "Invalid player number");

        if (n == 1) {
            if (player1 != address(0)) {
                revert HasRegistered(Role.Thief);
            }
            player1 = _msgSender();
        } else if (n == 2) {
            if (player2 != address(0)) {
                revert HasRegistered(Role.Police);
            }
            player2 = _msgSender();
        }

        emit Registered(_msgSender());

        if (player1 != address(0) && player2 != address(0)) {
            gameState = GameState.RoundOneInProgress;
            roles[Role.Thief] = player1;
            roles[Role.Police] = player2;
            currentRole = Role.Thief;
            thiefTime = block.timestamp + timeLimitPerTurn;
            emit GameStarted(player1, player2);
        }
    }

    function cancelRegistration() public gameNotStarted onlyPlayer {
        if (_msgSender() == player1) {
            player1 = address(0);
        } else if (_msgSender() == player2) {
            player2 = address(0);
        }
        emit CancelledRegistration(_msgSender());
    }

    function heist(uint256 score) private {
        if (gameState == GameState.RoundOneInProgress) {
            // round 1 ends
            scores[0] = score;
            gameState = GameState.RoundTwoInProgress;

            // interchange
            roles[Role.Thief] = player2;
            roles[Role.Police] = player1;
            currentRole = Role.Thief;
            thiefTime = block.timestamp + timeLimitPerTurn;
            commitment = 0;
            copUsedCount = 0;
            for (uint8 i = 0; i < MAX_COPS; i++) {
                ambushes[i] = [-1, -1];
            }
        } else if (gameState == GameState.RoundTwoInProgress) {
            // round 2 ends
            scores[1] = score;
            gameState = GameState.Ended;

            address winner;
            if (scores[0] > scores[1]) {
                winner = player1;
            } else if (scores[0] < scores[1]) {
                winner = player2;
            }

            emit GameEnded(winner, scores);
        }
    }

    function timeUp() public gameInProgress onlyPlayer returns (bool) {
        if (currentRole == Role.Thief && thiefTime < block.timestamp && _msgSender() == roles[Role.Police]) {
            // police wins
            heist(0);
            emit TimeUp(gameState, Role.Thief, roles[Role.Thief]);
            return true;
        } else if (currentRole == Role.Police && policeTime < block.timestamp && _msgSender() == roles[Role.Thief]) {
            // thief wins
            heist(timeUpPoints);
            emit TimeUp(gameState, Role.Police, roles[Role.Police]);
            return true;
        }
        return false;
    }

    function sneak(
        uint256[2] calldata _pA,
        uint256[2][2] calldata _pB,
        uint256[2] calldata _pC,
        uint256[13] calldata _pubSignals
    ) public onlyThief gameInProgress {
        if (copUsedCount == MAX_COPS) {
            revert ShouldReveal();
        }
        if (!isValidAmbushes(_pubSignals)) {
            revert InvalidAmbushes();
        }
        if (commitment > 0 && commitment != _pubSignals[0]) {
            revert InvalidCommitment();
        }

        if (!sneakVerifier.verifyProof(_pA, _pB, _pC, _pubSignals)) {
            revert InvalidProof();
        }

        commitment = _pubSignals[1];

        // change to player2's turn
        currentRole = Role.Police;
        policeTime = block.timestamp + timeLimitPerTurn;

        emit Sneak(gameState, roles[Role.Thief], _pubSignals[2] != 0);
    }

    /**
     * @dev theif's last move, also the game's last move
     * when theif can't call sneak, theif should call reveal
     *
     * Notice that if theif generates a wrong proof and reveal, theif will lose even if theif might win.
     * If the player1 think the proof would be correct, theif should call verifier.verifyProof at first to guarantee the proof is correct.
     */
    function reveal(
        int8[5] calldata _flattenedSneakPaths,
        uint256[2] calldata _pA,
        uint256[2][2] calldata _pB,
        uint256[2] calldata _pC,
        uint256[13] calldata _pubSignals,
        bool caught
    ) external onlyThief gameInProgress {
        uint256 hash = hashCommitment(_flattenedSneakPaths);

        if (hash != commitment || hash != _pubSignals[1]) {
            revert InvalidCommitment();
        }

        if (!caught && sneakVerifier.verifyProof(_pA, _pB, _pC, _pubSignals)) {
            if (!isValidAmbushes(_pubSignals)) {
                revert InvalidAmbushes();
            }

            // thief wins
            if (copUsedCount == MAX_COPS) {
                // calculate player1's score
                // feat: the path that has been walked cannot be calculated repeatedly
                bool[9] memory visited = [false, false, false, false, false, false, false, false, false];
                uint256 score = 0;
                for (uint8 i = 0; i < _flattenedSneakPaths.length; i++) {
                    // _sneakPaths value must be unsigned
                    if (_flattenedSneakPaths[i] < 0) {
                        revert InvalidSneakPath();
                    }
                    if (!visited[uint8(_flattenedSneakPaths[i])]) {
                        score += prizeMap[uint8(_flattenedSneakPaths[i])];
                    }
                    visited[uint8(_flattenedSneakPaths[i])] = true;
                }
                emit Reveal(caught, roles[Role.Thief], _flattenedSneakPaths);
                heist(score);
            } else {
                revert ShouldSneak();
            }
        } else if (caught) {
            // thief has been caught
            emit Reveal(caught, roles[Role.Thief], _flattenedSneakPaths);
            heist(0);
        } else {
            revert InvalidReveal();
        }
    }

    function dispatch(uint8 x, uint8 y) public onlyPolice gameInProgress {
        if (copUsedCount == MAX_COPS) {
            revert CopExhausted();
        }

        if (x > 2 || x < 0 || y > 2 || y < 0) {
            revert InvalidCoordinates();
        }

        if (ambushes[0][0] == -1 && ambushes[0][1] == -1) {
            ambushes[0][0] = int8(x);
            ambushes[0][1] = int8(y);
            copUsedCount++;
        } else {
            for (uint8 i = 0; i < MAX_COPS; i++) {
                if (ambushes[i][0] == int8(x) && ambushes[i][1] == int8(y)) {
                    revert AmbushExists();
                }

                if (ambushes[i][0] == -1 && ambushes[i][1] == -1) {
                    ambushes[i][0] = int8(x);
                    ambushes[i][1] = int8(y);
                    copUsedCount++;
                    break;
                }
            }
        }

        // change to player1's turn
        currentRole = Role.Thief;
        thiefTime = block.timestamp + timeLimitPerTurn;

        emit Dispatch(gameState, roles[Role.Police]);
    }

    // ================================ Errors ================================
    error PoseidonT6NotLinked();
    error HasRegistered(Role);
    error InvalidProof();
    error InvalidCommitment();
    error InvalidAmbushes();
    error ShouldReveal();
    error ShouldSneak();
    error InvalidSneakPath();
    error InvalidCoordinates();
    error CopExhausted();
    error AmbushExists();
    error InvalidReveal();

    // ================================ View functions ================================

    function currentPlayer() public view returns (address) {
        return roles[currentRole];
    }

    function theifTimeLeft() public view returns (uint256) {
        if (currentRole == Role.Thief) {
            return thiefTime - block.timestamp;
        }
        return 0;
    }

    function policeTimeLeft() public view returns (uint256) {
        if (currentRole == Role.Police) {
            return policeTime - block.timestamp;
        }
        return 0;
    }

    function flattenedAmbushes() public view returns (int8[10] memory) {
        int8[10] memory res;
        for (uint8 i = 0; i < MAX_COPS; i++) {
            res[i * 2] = ambushes[i][0];
            res[i * 2 + 1] = ambushes[i][1];
        }
        return res;
    }

    function isValidAmbushes(uint256[13] calldata _pubSignals) public view returns (bool) {
        uint256 negativeOne = 21888242871839275222246405745257275088548364400416034343698204186575808495616;
        for (uint8 i = 3; i < 13; i++) {
            if (flattenedAmbushes()[i - 3] == int8(-1)) {
                if (_pubSignals[i] != negativeOne) {
                    return false;
                }
            } else if (_pubSignals[i] != uint256(uint8(flattenedAmbushes()[i - 3]))) {
                return false;
            }
        }
        return true;
    }

    function hashCommitment(int8[5] memory _coordinates) public pure returns (uint256) {
        uint256 negativeOne = 21888242871839275222246405745257275088548364400416034343698204186575808495616;
        return PoseidonT6.hash(
            [
                _coordinates[0] == -1 ? negativeOne : uint256(uint8(_coordinates[0])),
                _coordinates[1] == -1 ? negativeOne : uint256(uint8(_coordinates[1])),
                _coordinates[2] == -1 ? negativeOne : uint256(uint8(_coordinates[2])),
                _coordinates[3] == -1 ? negativeOne : uint256(uint8(_coordinates[3])),
                _coordinates[4] == -1 ? negativeOne : uint256(uint8(_coordinates[4]))
            ]
        );
    }

    // ================================ Modifiers ================================

    modifier onlyThief() {
        require(_msgSender() == roles[Role.Thief], "Only player1 can call this function");
        _;
    }

    modifier onlyPolice() {
        require(_msgSender() == roles[Role.Police], "Only player2 can call this function");
        _;
    }

    modifier onlyPlayer() {
        require(_msgSender() == player1 || _msgSender() == player2, "Only players can call this function");
        _;
    }

    modifier gameNotStarted() {
        require(gameState == GameState.NotStarted, "Game is already in progress or ended");
        _;
    }

    modifier gameInProgress() {
        require(
            gameState == GameState.RoundOneInProgress || gameState == GameState.RoundTwoInProgress,
            "Game is not in progress"
        );
        _;
    }

    modifier gameEnded() {
        require(gameState == GameState.Ended, "Game has not ended yet");
        _;
    }
}
