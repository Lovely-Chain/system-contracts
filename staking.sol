// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;


interface InterfaceValidator {
    enum Status {
        // validator not exist, default status
        NotExist,
        // validator created
        Created,
        // anyone has staked for the validator
        Staked,
        // validator's staked coins < MinimalStakingCoin
        Unstaked,
        // validator is jailed by system(validator have to repropose)
        Jailed
    }
    struct Description {
        string moniker;
        string identity;
        string website;
        string email;
        string details;
    }
    function getTopValidators() external view returns(address[] memory);
    function getValidatorInfo(address val)external view returns(address payable, Status, uint256, uint256, uint256, address[] memory);
    function getValidatorDescription(address val) external view returns ( string memory,string memory,string memory,string memory,string memory);
    function totalStake() external view returns(uint256);
    function getStakingInfo(address staker, address validator) external view returns(uint256, uint256, uint256);
    function viewStakeReward(address _staker, address _validator) external view returns(uint256);
    function MinimalStakingCoin() external view returns(uint256);
    function minimumValidatorStaking() external view returns(uint256);
    function isTopValidator(address who) external view returns (bool);
    function StakingLockPeriod() external view returns(uint64);
    function UnstakeLockPeriod() external view returns(uint64);
    function WithdrawProfitPeriod() external view returns(uint64);
    function totalStakers() external view returns(uint256);

    //write functions
    function createOrEditValidator(
        address payable feeAddr,
        string calldata moniker,
        string calldata identity,
        string calldata website,
        string calldata email,
        string calldata details
    ) external payable  returns (bool);

    function unstake(address validator)
        external
        returns (bool);
    function withdrawStaking(address validator)
        external
        returns (bool);
    function stake(address validator) external payable returns (bool);
    function withdrawProfits(address validator) external returns (bool);
}


/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract ValidatorHelper is Ownable {

    InterfaceValidator public valContract = InterfaceValidator(0xff43f3BF4a5c07140f77F20150207ea8237cBc4f);
    uint256 public minimumValidatorStaking ;
    uint256 public lastRewardedBlock ; //last reward distributed block
    uint256 public NextRewardBlock ; // current block will be set at deploy time
    uint256 public rewardIntervalBlock = 21024000; // block intervals during 2 years
    uint256 public extraRewardsPerBlock ; //extra rewards to be distributed for a block
    uint256 public rewardFund; // fund given to the contract for reward distribution
    uint256 public rewardAllocation ; // part of the fund allocated to get distributed for 2 years
    mapping(address=>uint256) public totalProfitWithdrawn; //profit withdrawn by the staker
    mapping(address=>uint256) public rewardDebt; // rewards assigned to the staker as dept
    uint256 public accTokenPerShare; //accumulated reward tokens for a holing token
    uint256 public totalStaking; // total staked amount by all the stakers
    mapping(address=>uint256) public userTotalStake; // total staked amount by a staker
    mapping(address=>uint256) public validatorTotalStake; // total staked amount of a validator
    mapping(address=>uint256) public validatorTotalStakers; // total staker of a validator
    mapping(address=>mapping(address=>uint256)) public uservalidatorStakes; //total stakes of a staker under a validator
    mapping(address => bool) public isWhitelisted; //whitelist the address to avoid penalty fee
    struct StakingInfo
    {
        uint256 amount;
        uint entertime;
    }
    mapping(address=>mapping(address=>StakingInfo[])) public stakerData; //staking info of a staker
    address payable public redeemWallet; // wallet to send penalty fees
    bool public isFeeApplicable = true; // toggle penalty fees applicable
    //events
    event Stake(address indexed staker, address indexed validator, uint256 amount, uint256 stakeindex, uint256 timestamp);
    event Unstake(address indexed staker, uint _index, uint256 amount, uint256 fee, uint256 timestamp);
    event WithdrawProfit(address indexed staker, uint256 amount, uint256 timestamp);
    event WithdrawStaking(address indexed _user, address indexed validator, uint256 amount, uint256 timestamp);

    receive() external payable {
        rewardFund += msg.value;
    }
    constructor() {
        redeemWallet = payable(msg.sender); //avoid address(0) getting penalty fee
        NextRewardBlock = block.number ;
        lastRewardedBlock = block.number;
        minimumValidatorStaking = valContract.minimumValidatorStaking();
    }
    function updatedValidator(address _val) external
    {
        valContract = InterfaceValidator(_val);
    }
    //This function is used to clear the pending rewards before stake, unstake and withdrawStaking
    function clearPendings(address _user, address validator) internal{
        bool IsNotValid;
        if(_user == validator)
        {
            (,InterfaceValidator.Status validatorStatus, , , , )  = valContract.getValidatorInfo(validator);
            if(validatorStatus == InterfaceValidator.Status.Jailed || validatorStatus == InterfaceValidator.Status.NotExist || validatorStatus == InterfaceValidator.Status.Created ){
              IsNotValid = true;
            }
        }
        (uint256 coinstaked, uint256 unstakedBlock ,  ) = valContract.getStakingInfo(_user, validator);
        coinstaked += userTotalStake[_user];
        if(coinstaked > 0 && unstakedBlock==0 && IsNotValid == false)
        {
          uint256 pending = (coinstaked * accTokenPerShare / 1e18) - rewardDebt[_user];
          if(pending > 0 && rewardAllocation>= pending) {
              totalProfitWithdrawn[_user] += pending;
              payable(_user).transfer(pending);
              rewardAllocation -= pending;
          }
        }
    }
    //This function is used to create new validator and store it's staking info
    function createOrEditValidator(
        address payable feeAddr,
        string calldata moniker,
        string calldata identity,
        string calldata website,
        string calldata email,
        string calldata details
    ) external payable  returns (bool) {
        if(stakerData[msg.sender][msg.sender].length >0)
        {
            stake(msg.sender);
        }
        else{
            _distributeRewards();
            require(msg.value >= minimumValidatorStaking, "Please stake minimum validator staking" );
            valContract.createOrEditValidator{value: msg.value}(feeAddr, moniker, identity, website, email, details);
            rewardDebt[msg.sender] = rewardDebt[msg.sender] + (msg.value * accTokenPerShare/1e18);
            StakingInfo memory st=StakingInfo(msg.value,block.timestamp);
            stakerData[msg.sender][msg.sender].push(st);
            emit Stake(msg.sender, msg.sender, msg.value, 0, block.timestamp);
        }
        return true;
    }
    //This function is used to stake as staker. All the coins staked by this function will be stored in this contracts
    //stakers can stake multiple time
    function stake(address validator)
        public payable
        returns (bool)
    {
        (, InterfaceValidator.Status status, uint256 coins, , , ) = valContract.getValidatorInfo(validator);
        require(status == InterfaceValidator.Status.Staked && coins>0, "Invalid Validator" );
        uint256 staking = msg.value;
        require(staking > 0, "No amount to stake");
        require(staking >= valContract.MinimalStakingCoin(), "Less than enforced MinimalStakingCoin limit");
        _distributeRewards();
        if(stakerData[msg.sender][validator].length >0)
        {
            clearPendings(msg.sender, validator);
        }
        else{
            validatorTotalStakers[validator] +=1;
        }
        rewardDebt[msg.sender] = rewardDebt[msg.sender] + (staking * accTokenPerShare/1e18);
        StakingInfo memory st=StakingInfo(staking,block.timestamp);
        stakerData[msg.sender][validator].push(st);
        totalStaking += staking;
        userTotalStake[msg.sender] += staking;
        validatorTotalStake[validator] += staking;
        uservalidatorStakes[msg.sender][validator] += staking;
        emit Stake(msg.sender, validator, staking, stakerData[msg.sender][validator].length - 1, block.timestamp);
        return true;
    }
    //This function is used to unstake the staked amount by index of the staking
    //if index==0 and caller is validator then his staking from validator contract will be unstake
    //if a staker unstake before the time, penalty fee will be applied on his staked amount
    function unstake(address validator, uint _index)
        external
        returns (bool)
    {
        require(stakerData[msg.sender][validator][_index].amount > 0, "No staking");
        _distributeRewards();
        clearPendings(msg.sender, validator);
        rewardDebt[msg.sender] = 0;
        if(validator == msg.sender && _index==0)
        {
            valContract.unstake(validator);
            stakerData[msg.sender][validator][_index].amount = 0;
            stakerData[msg.sender][validator][_index].entertime = 0;
            emit Unstake(msg.sender, _index, 0, 0, block.timestamp);
        }
        else{
            uint256 staking = stakerData[msg.sender][validator][_index].amount;
            uint stakingDuration = (block.timestamp
                                    - stakerData[msg.sender][validator][_index].entertime)
                                    / 100 ; //86400
            totalStaking -= staking;
            userTotalStake[msg.sender] -= staking;
            validatorTotalStake[validator] -= staking;
            uservalidatorStakes[msg.sender][validator] -= staking;
            uint256 redeemFee;
            if(isFeeApplicable && !isWhitelisted[msg.sender]){
              if(stakingDuration < 7)
              {
                  redeemFee = (staking*5/1000); //redeem fee 0.5%
              }
              else if(stakingDuration < 15)
              {
                  redeemFee = (staking*2/1000); //redeem fee 0.2%
              }
              else if(stakingDuration < 30)
              {
                  redeemFee = (staking/1000); //redeem fee 0.1%
              }
              else if(stakingDuration < 60)
              {
                  redeemFee = (staking*5/10000); //redeem fee 0.05%
              }
              if(redeemFee > 0)
              {
                  redeemWallet.transfer(redeemFee);
              }
              staking -=redeemFee;
            }
            stakerData[msg.sender][validator][_index].amount = 0;
            stakerData[msg.sender][validator][_index].entertime = 0;
            if(uservalidatorStakes[msg.sender][validator] == 0)
            {
                validatorTotalStakers[validator] -= 1;
            }
            payable(msg.sender).transfer(staking);
            emit Unstake(msg.sender, _index, staking, redeemFee, block.timestamp);
        }

        return true;
    }
    //This function is used to withdraw staking of a staker
    function withdrawStaking(address validator, uint _index)
        external
        returns (bool)
    {
        require(msg.sender == validator && _index==0, "Invalid staking");
        _distributeRewards();
        clearPendings(msg.sender, validator);
        rewardDebt[msg.sender] = 0;
        uint256 staking = stakerData[msg.sender][validator][_index].amount;
        valContract.withdrawStaking(validator);
        stakerData[msg.sender][validator][_index].amount = 0;
        stakerData[msg.sender][validator][_index].entertime = 0;
        emit WithdrawStaking(msg.sender, validator, staking, block.timestamp);
        return true;
    }
    //This function is used to withdraw staking rewards of a staker
    function withdrawStakingReward(address validator) external {
       // require(validator == tx.origin, "caller should be real validator");
        uint256 blockRewards = viewValidatorRewards(msg.sender, validator);
        require(blockRewards > 0, "Nothing to withdraw");
        _distributeRewards();

        if(msg.sender == validator){
	     valContract.withdrawProfits(validator);
        }
        if(rewardAllocation >= blockRewards ){
          rewardAllocation -= blockRewards;
          rewardDebt[msg.sender] += blockRewards;
          totalProfitWithdrawn[msg.sender] += blockRewards;
          payable(msg.sender).transfer(blockRewards);
          emit WithdrawProfit( msg.sender,  blockRewards,  block.timestamp);
        }
    }
    //This function is used to show staker's rewards
    function viewValidatorRewards(address staker, address validator) public view returns(uint256 rewardAmount){
      uint256 coinstaked;
      uint256 unstakeBlock;
      if(validator == staker){
        (coinstaked,  unstakeBlock,  ) = valContract.getStakingInfo(staker, validator);
      }
      coinstaked += userTotalStake[staker];
      if(coinstaked>0 && unstakeBlock == 0){
        rewardAmount = ((coinstaked * accTokenPerShare)/1e18) - rewardDebt[staker];
      }
    }
    //This function is used to distribute reards among all the stakers
    function _distributeRewards() public {

        if(NextRewardBlock <= block.number && rewardFund > 0)
        {
          uint256 tempAllocation = (rewardFund * 40)/100;
          rewardFund = rewardFund - tempAllocation ;
          rewardAllocation += tempAllocation;
          extraRewardsPerBlock = tempAllocation / rewardIntervalBlock ;
          NextRewardBlock +=  rewardIntervalBlock;
        }
        if(rewardAllocation > 0){
            uint256 totalstake = valContract.totalStake() + totalStaking;
            uint256 tokenReward = (block.number - lastRewardedBlock) * extraRewardsPerBlock;
            if( totalstake > 0){
                accTokenPerShare = accTokenPerShare + (tokenReward * 1e18 / totalstake);
            }
        }
        lastRewardedBlock = block.number;
    }

    /**
        admin functions
    */
    //admin can withdraw reward fund from contract's balance using this function
    function rescueCoins(bool includeAllocation) external onlyOwner{
        uint256 total = rewardFund;
        rewardFund = 0;
        if(includeAllocation){
            total += rewardAllocation;
            rewardAllocation = 0;
        }
        payable(msg.sender).transfer(total);
    }
    function changeMinimumValidatorStaking(uint256 amount) external onlyOwner{
        minimumValidatorStaking = amount;
    }
    function setRedeemWallet(address payable _wallet) external onlyOwner
    {
        require(_wallet != address(0), "Invalid address");
        redeemWallet = _wallet;
    }
    function setRewardBlock(uint256 _NextRewardBlock, uint256 _rewardIntervalBlock)  external onlyOwner
    {
      require(_NextRewardBlock >= block.number && _rewardIntervalBlock > 0,'Invalid values');
      NextRewardBlock = _NextRewardBlock;
      rewardIntervalBlock = _rewardIntervalBlock;
    }
    function toggleFeeApplicable(bool _isFeeApplicable) external onlyOwner
    {
        isFeeApplicable = _isFeeApplicable;
    }
    function updateIsWhitelisted(address _address, bool _flag) external onlyOwner
    {
        isWhitelisted[_address] = _flag;
    }

    /**
        View functions
    */

    function getAllValidatorInfo() external view returns (uint256 totalValidatorCount,uint256 totalStakedCoins,address[] memory,InterfaceValidator.Status[] memory,uint256[] memory,string[] memory,string[] memory)
    {
        address[] memory highestValidatorsSet = valContract.getTopValidators();

        uint256 totalValidators = highestValidatorsSet.length;
	     uint256 totalunstaked ;
        InterfaceValidator.Status[] memory statusArray = new InterfaceValidator.Status[](totalValidators);
        uint256[] memory coinsArray = new uint256[](totalValidators);
        string[] memory identityArray = new string[](totalValidators);
        string[] memory websiteArray = new string[](totalValidators);

        for(uint8 i=0; i < totalValidators; i++){
            (, InterfaceValidator.Status status, uint256 coins, , , ) = valContract.getValidatorInfo(highestValidatorsSet[i]);
            if(coins>0 ){
                (, string memory identity, string memory website, ,) = valContract.getValidatorDescription(highestValidatorsSet[i]);
                coins += validatorTotalStake[highestValidatorsSet[i]];
                statusArray[i] = status;
                coinsArray[i] = coins;
                identityArray[i] = identity;
                websiteArray[i] = website;
            }
            else
            {
                totalunstaked += 1;
            }
        }
        return(totalValidators - totalunstaked , valContract.totalStake(), highestValidatorsSet, statusArray, coinsArray, identityArray, websiteArray);
    }

    function validatorSpecificInfo1(address validatorAddress, address user) external view returns(string memory identityName, string memory website, string memory otherDetails, uint256 withdrawableRewards, uint256 stakedCoins, uint256 waitingBlocksForUnstake ){

        (, string memory identity, string memory websiteLocal, ,string memory details) = valContract.getValidatorDescription(validatorAddress);

        uint256 unstakeBlock;
        (stakedCoins, unstakeBlock, ) = valContract.getStakingInfo(validatorAddress,validatorAddress);

        if(unstakeBlock!=0){
            waitingBlocksForUnstake = stakedCoins;
            stakedCoins = 0;
        }
        withdrawableRewards = viewValidatorRewards(user, validatorAddress);
        return(identity, websiteLocal, details, withdrawableRewards, stakedCoins, waitingBlocksForUnstake) ;
    }


    function validatorSpecificInfo2(address validatorAddress, address user) external view returns(uint256 totalStakedCoins, InterfaceValidator.Status status, uint256 selfStakedCoins, uint256 masterVoters, uint256 stakers, address){
        address[] memory stakersArray;
        (, status, totalStakedCoins, , , stakersArray)  = valContract.getValidatorInfo(validatorAddress);
        totalStakedCoins += validatorTotalStake[validatorAddress];

        (selfStakedCoins, , ) = valContract.getStakingInfo(validatorAddress,validatorAddress);
        selfStakedCoins += userTotalStake[validatorAddress];
        stakers = stakersArray.length + validatorTotalStakers[validatorAddress];
        return (totalStakedCoins, status, selfStakedCoins, 0, stakers, user);
    }



    function totalProfitEarned(address user, address validator) public view returns(uint256){
        return totalProfitWithdrawn[user] + viewValidatorRewards(user, validator);
    }

    function waitingWithdrawProfit(address user, address validatorAddress) external view returns(uint256){
        // no waiting to withdraw profit.
        // this is kept for backward UI compatibility

       return 0;
    }

    function waitingUnstaking(address user, address validator) external view returns(uint256){

        //this function is kept as it is for the UI compatibility
        //no waiting for unstaking
        return 0;
    }

    function waitingWithdrawStaking(address user, address validatorAddress) public view returns(uint256){

        //validator and delegators will have waiting

        (, uint256 unstakeBlock, ) = valContract.getStakingInfo(user,validatorAddress);

        if(unstakeBlock==0){
            return 0;
        }

        if(unstakeBlock + valContract.StakingLockPeriod() > block.number){
            return 2 * ((unstakeBlock + valContract.StakingLockPeriod()) - block.number);
        }

       return 0;

    }

    function minimumStakingAmount() public view returns(uint256){
        return valContract.MinimalStakingCoin();
    }

    function stakingValidations(address user, address validatorAddress) external view returns(uint256 minimumStakingAmt, uint256 stakingWaiting){
        return (valContract.MinimalStakingCoin(), waitingWithdrawStaking(user, validatorAddress));
    }

    function checkValidator(address user) external view returns(bool){
        //this function is for UI compatibility
        return true;
    }
    function getStakingInfo(address staker, address val, uint _index)
        public
        view
        returns (
            uint256,
            uint256
        )
    {
        return (
            stakerData[staker][val][_index].amount,
            stakerData[staker][val][_index].entertime

        );
    }
    function getStakingLen(address staker, address val)
        public
        view
        returns (
            uint256
        )
    {
        return stakerData[staker][val].length;
    }
}
