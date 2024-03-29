//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


// |============================================================================================|
// |    ______      _____    __      _____    __   __       _____     _____   __  __   ______   |
// |   /_/\___\    ) ___ (  /\_\    /\ __/\  /\_\ /\_\     ) ___ (   /\ __/\ /\_\\  /\/ ____/\  |
// |   ) ) ___/   / /\_/\ \( ( (    ) )  \ \ \/_/( ( (    / /\_/\ \  ) )__\/( ( (/ / /) ) __\/  |
// |  /_/ /  ___ / /_/ (_\ \\ \_\  / / /\ \ \ /\_\\ \_\  / /_/ (_\ \/ / /    \ \_ / /  \ \ \    |
// |  \ \ \_/\__\\ \ )_/ / // / /__\ \ \/ / // / // / /__\ \ )_/ / /\ \ \_   / /  \ \  _\ \ \   |
// |   )_)  \/ _/ \ \/_\/ /( (_____() )__/ /( (_(( (_____(\ \/_\/ /  ) )__/\( (_(\ \ \)____) )  |
// |   \_\____/    )_____(  \/_____/\/___\/  \/_/ \/_____/ )_____(   \/___\/ \/_//__\/\____\/   |
// |                                                                                            |
// |============================================================================================|
// ==============================================================================================
// ========================================= Porridge ===========================================
// ==============================================================================================


//todo: fix reentrancy bug
import { ERC20 } from "../../lib/solady/src/tokens/ERC20.sol";
import { SafeTransferLib } from "../../lib/solady/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/solady/src/utils/FixedPointMathLib.sol";
import { IBorrow } from "../interfaces/IBorrow.sol";
import { IGoldiswap } from "../interfaces/IGoldiswap.sol";


/// @title Porridge
/// @notice Staking of the $LOCKS token to earn $PRG
/// @author geeb
/// @author ampnoob
contract Porridge is ERC20 {


  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                      STATE VARIABLES                       */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


  uint32 public immutable DAYS_SECONDS = 86400;
  uint16 public immutable DAILY_EMISSISION_RATE = 600;

  mapping(address => uint256) public staked;
  mapping(address => uint256) public stakeStartTime;

  address public goldiswap;
  address public borrow;
  address public multisig;
  address public honey;


  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                          CONSTRUCTOR                       */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


  /// @notice Constructor of this contract
  /// @param _goldiswap Address of Goldiswap
  /// @param _honey Address of the HONEY contract
  constructor(
    address _goldiswap, 
    address _honey
  ) {
    multisig = msg.sender;
    goldiswap = _goldiswap;
    honey = _honey;
  }

  /// @notice Returns the name of the $PRG token
  function name() public pure override returns (string memory) {
    return "Porridge Token";
  }

  /// @notice Returns the symbol of the $PRG token
  function symbol() public pure override returns (string memory) {
    return "PRG";
  }


  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                           ERRORS                           */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


  error NotMultisig();
  error InvalidUnstake();
  error LocksBorrowedAgainst();


  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                           EVENTS                           */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


  event Staked(address indexed user, uint256 amount);
  event Unstaked(address indexed user, uint256 amount);
  event Realized(address indexed user, uint256 amount);
  event Claimed(address indexed user, uint256 amount);


  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                         MODIFIERS                          */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


  /// @notice Ensures msg.sender is GoldilocksDAO multisig
  modifier onlyMultisig() {
    if(msg.sender != multisig) revert NotMultisig();
    _;
  }


  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                       VIEW FUNCTIONS                       */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


  /// @notice Returns the staked $LOCKS of an address
  /// @param user Address to view staked $LOCKS
  function getStaked(address user) external view returns (uint256) {
    return staked[user];
  }

  /// @notice Returns the stake start time of an address
  /// @param user Address to view stake start time
  function getStakeStartTime(address user) external view returns (uint256) {
    return stakeStartTime[user];
  }

  /// @notice Returns the claimable yield of an address
  /// @param user Address to view claimable yield
  function getClaimable(address user) external view returns (uint256) {
    uint256 stakedAmount = staked[user];
    return _calculateClaimable(user, stakedAmount);
  }


  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                    EXTERNAL FUNCTIONS                      */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


  /// @notice Stakes $LOCKS and begins earning $PRG
  /// @param amount Amount of $LOCKS to stake
  function stake(uint256 amount) external {
    if(staked[msg.sender] > 0) {
      _stakeClaim();
    }
    stakeStartTime[msg.sender] = block.timestamp;
    staked[msg.sender] += amount;
    SafeTransferLib.safeTransferFrom(goldiswap, msg.sender, address(this), amount);
    emit Staked(msg.sender, amount);
  }

  /// @notice Unstakes $LOCKS and claims $PRG 
  /// @param amount Amount of $LOCKS to unstake
  function unstake(uint256 amount) external {
    if(amount > staked[msg.sender]) revert InvalidUnstake();
    if(amount > staked[msg.sender] - IBorrow(borrow).getLocked(msg.sender)) revert LocksBorrowedAgainst();
    uint256 stakedAmount = staked[msg.sender];
    staked[msg.sender] -= amount;
    _claim(stakedAmount);
    SafeTransferLib.safeTransfer(goldiswap, msg.sender, amount);
    emit Unstaked(msg.sender, amount);
  }

  /// @notice Burns $PRG to buy $LOCKS at floor price
  /// @param amount Amount of $PRG to burn
  function realize(uint256 amount) external {
    _burn(msg.sender, amount);
    SafeTransferLib.safeTransferFrom(honey, msg.sender, goldiswap, FixedPointMathLib.mulWad(amount, IGoldiswap(goldiswap).floorPrice()));
    IGoldiswap(goldiswap).porridgeMint(msg.sender, amount);
    emit Realized(msg.sender, amount);
  }

  /// @notice Claim $PRG rewards
  function claim() external {
    uint256 stakedAmount = staked[msg.sender];
    _claim(stakedAmount);
  }


  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                      INTERNAL FUNCTIONS                    */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


  /// @notice Calculates and distributes yield
  /// @param stakedAmount Amount of $LOCKS the user has staked in the contract
  function _claim(uint256 stakedAmount) internal {
    uint256 claimable = _calculateClaimable(msg.sender, stakedAmount);
    if(claimable > 0) {
      stakeStartTime[msg.sender] = block.timestamp;
      _mint(msg.sender, claimable);
      emit Claimed(msg.sender, claimable);
    }
  }

  /// @notice Calculates and distributes yield from stake function
  function _stakeClaim() internal {
    uint256 stakedAmount = staked[msg.sender];
    uint256 claimable = _calculateClaimable(msg.sender, stakedAmount);
    if(claimable > 0) {
      _mint(msg.sender, claimable);
      emit Claimed(msg.sender, claimable);
    }
  }
    
  /// @notice Calculates claimable yield
  /// @dev claimable = (staked $LOCKS / daily emission rate) * days staked
  /// @param user Address of staker to calculate yield
  /// @param stakedAmount Amount of $LOCKS the user has staked in the contract
  /// @return yield Amount of $PRG earned by staker
  function _calculateClaimable(
    address user, 
    uint256 stakedAmount
  ) internal view returns (uint256 yield) {
    uint256 timeStaked = _timeStaked(user);
    uint256 yieldPortion = stakedAmount / DAILY_EMISSISION_RATE;
    yield = FixedPointMathLib.mulWad(yieldPortion, FixedPointMathLib.divWad(timeStaked, DAYS_SECONDS));
  }

  /// @notice Calculates time staked of a staker
  /// @param user Address of staker to find time staked
  /// @return timeStaked staked of an address
  function _timeStaked(address user) internal view returns (uint256 timeStaked) {
    timeStaked = block.timestamp - stakeStartTime[user];
  }


  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                   PERMISSIONED FUNCTIONS                   */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


  /// @notice Changes the address of the multisig address
  /// @dev Used after deployment by deployment address
  /// @param _multisig Address of the multisig
  function setMultisig(address _multisig) external onlyMultisig {
    multisig = _multisig;
  }

  function setBorrow(address _borrow) external onlyMultisig {
    borrow = _borrow;
  }

}