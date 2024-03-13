pragma solidity ^0.8.0;

contract CHGControl {
    mapping(address => address) public controlledAddresses;
    mapping(address => bool) public isAdmin;

    modifier onlyAdmin() {
        require(isAdmin[msg.sender], "Only admins can call this function");
        _;
    }

    modifier onlyControlled() {
        require(controlledAddresses[msg.sender] != address(0), "Only controlled addresses can call this function");
        _;
    }

    function addAdmin(address newAdmin) public onlyAdmin {
        isAdmin[newAdmin] = true;
    }

    function removeAdmin(address adminToRemove) public onlyAdmin {
        require(adminToRemove != msg.sender, "Cannot remove yourself as admin");
        isAdmin[adminToRemove] = false;
    }

    function authorizeControl(address controlledAddress) public onlyAdmin {
        controlledAddresses[controlledAddress] = msg.sender;
    }

    function revokeControl(address controlledAddress) public onlyAdmin {
        require(controlledAddresses[controlledAddress] == msg.sender, "Not authorized to revoke control");
        controlledAddresses[controlledAddress] = address(0);
    }
}

contract P2PLending {
    struct Collateral {
        string assetType;
        string assetID;
        uint256 value;
    }

    struct Transaction {
        uint256 amount;
        uint256 timestamp;
    }

    Collateral public collateral;
    address public owner;
    uint256 public loanAmount;
    uint256 public interestRate;
    uint256 public termLength;
    address public borrower;
    address public weChargAddress;
    address public chargingStationOwnerAddress;
    uint256 public weChargProfitPercentBeforeEpoch; // Profit percent for WeCharg before epoch
    uint256 public chargingStationOwnerProfitPercentBeforeEpoch; // Profit percent for charging station owner before epoch
    uint256 public weChargProfitPercentAfterEpoch; // Profit percent for WeCharg after epoch
    uint256 public chargingStationOwnerProfitPercentAfterEpoch; // Profit percent for charging station owner after epoch
    uint256 public landOwnerProfitPercentBeforeEpoch; // Profit percent for land owner before epoch
    uint256 public landOwnerProfitPercentAfterEpoch; // Profit percent for land owner after epoch
    uint256 public numMLMTiers; // Number of MLM tiers
    mapping(uint256 => address) public mlmTiers; // Mapping of MLM tier index to address
    mapping(address => uint256) public mlmTierProfitPercent; // Profit percent for each MLM tier

    mapping(address => Transaction[]) public oldContractProceeds; // Proceeds from the old contract per CHG address

    mapping(address => uint256) public pendingProceeds;

    modifier onlyAgent() {
        require(msg.sender == chargingStationOwnerAddress, "Only the charging station owner can call this function");
        _;
    }

    modifier onlyWeCharg() {
        require(msg.sender == weChargAddress, "Only WeCharg can call this function");
        _;
    }

    modifier onlyCHGControl() {
        require(msg.sender == chgControlAddress, "Only CHGControl contract can call this function");
        _;
    }

    CHGControl public chgControl;
    address public chgControlAddress;

    constructor(address _chgControlAddress) {
        chgControl = CHGControl(_chgControlAddress);
        chgControlAddress = _chgControlAddress;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the contract owner can call this function");
        _;
    }

    event LoanRepaid(uint256 amount);
    event ProceedsWithdrawn(address recipient, uint256 amount);
    event LoanTransfer(address newBorrower);

    function initialize(
        Collateral memory _collateral,
        uint256 _loanAmount,
        uint256 _interestRate,
        uint256 _termLength,
        address _borrower,
        address _weChargAddress,
        address _chargingStationOwnerAddress,
        uint256 _weChargProfitPercentBeforeEpoch,
        uint256 _chargingStationOwnerProfitPercentBeforeEpoch,
        uint256 _weChargProfitPercentAfterEpoch,
        uint256 _chargingStationOwnerProfitPercentAfterEpoch,
        uint256 _landOwnerProfitPercentBeforeEpoch,
        uint256 _landOwnerProfitPercentAfterEpoch,
        uint256 _numMLMTiers,
        address[] memory _mlmTiers,
        uint256[] memory _mlmTierProfitPercent
    ) external onlyOwner {
        require(owner == address(0), "Contract has already been initialized");

        collateral = _collateral;
        loanAmount = _loanAmount;
        interestRate = _interestRate;
        termLength = _termLength;
        borrower = _borrower;
        weChargAddress = _weChargAddress;
        chargingStationOwnerAddress = _chargingStationOwnerAddress;
        weChargProfitPercentBeforeEpoch = _weChargProfitPercentBeforeEpoch;
        chargingStationOwnerProfitPercentBeforeEpoch = _chargingStationOwnerProfitPercentBeforeEpoch;
        weChargProfitPercentAfterEpoch = _weChargProfitPercentAfterEpoch;
        chargingStationOwnerProfitPercentAfterEpoch = _chargingStationOwnerProfitPercentAfterEpoch;
        landOwnerProfitPercentBeforeEpoch = _landOwnerProfitPercentBeforeEpoch;
        landOwnerProfitPercentAfterEpoch = _landOwnerProfitPercentAfterEpoch;
        numMLMTiers = _numMLMTiers;

        require(
            _mlmTiers.length == _mlmTierProfitPercent.length,
            "Number of MLM tiers and profit percentages mismatch"
        );

        for (uint256 i = 0; i < _mlmTiers.length; i++) {
            mlmTiers[i] = _mlmTiers[i];
            mlmTierProfitPercent[_mlmTiers[i]] = _mlmTierProfitPercent[i];
        }

        owner = msg.sender;
    }

    function updateCollateral(Collateral memory _collateral) external onlyOwner {
        collateral = _collateral;
    }

    function updateLoanAmount(uint256 _loanAmount) external onlyOwner {
        loanAmount = _loanAmount;
    }

    function updateInterestRate(uint256 _interestRate) external onlyOwner {
        interestRate = _interestRate;
    }

    function updateTermLength(uint256 _termLength) external onlyOwner {
        termLength = _termLength;
    }

    function updateBorrower(address _borrower) external onlyOwner {
        borrower = _borrower;
    }

    function updateWeChargAddress(address _weChargAddress) external onlyOwner {
        weChargAddress = _weChargAddress;
    }

    function updateChargingStationOwnerAddress(address _chargingStationOwnerAddress) external onlyOwner {
        chargingStationOwnerAddress = _chargingStationOwnerAddress;
    }

    function updateWeChargProfitPercentBeforeEpoch(uint256 _weChargProfitPercentBeforeEpoch) external onlyOwner {
        weChargProfitPercentBeforeEpoch = _weChargProfitPercentBeforeEpoch;
    }

    function updateChargingStationOwnerProfitPercentBeforeEpoch(
        uint256 _chargingStationOwnerProfitPercentBeforeEpoch
    ) external onlyOwner {
        chargingStationOwnerProfitPercentBeforeEpoch = _chargingStationOwnerProfitPercentBeforeEpoch;
    }

    function updateWeChargProfitPercentAfterEpoch(uint256 _weChargProfitPercentAfterEpoch) external onlyOwner {
        weChargProfitPercentAfterEpoch = _weChargProfitPercentAfterEpoch;
    }

    function updateChargingStationOwnerProfitPercentAfterEpoch(uint256 _chargingStationOwnerProfitPercentAfterEpoch)
        external
        onlyOwner
    {
        chargingStationOwnerProfitPercentAfterEpoch = _chargingStationOwnerProfitPercentAfterEpoch;
    }

    function updateLandOwnerProfitPercentBeforeEpoch(uint256 _landOwnerProfitPercentBeforeEpoch) external onlyOwner {
        landOwnerProfitPercentBeforeEpoch = _landOwnerProfitPercentBeforeEpoch;
    }

    function updateLandOwnerProfitPercentAfterEpoch(uint256 _landOwnerProfitPercentAfterEpoch) external onlyOwner {
        landOwnerProfitPercentAfterEpoch = _landOwnerProfitPercentAfterEpoch;
    }

    function updateNumMLMTiers(uint256 _numMLMTiers) external onlyOwner {
        numMLMTiers = _numMLMTiers;
    }

    function updateMLMTier(address _mlmTier, uint256 _index) external onlyOwner {
        mlmTiers[_index] = _mlmTier;
    }

    function updateMLMTierProfitPercent(address _mlmTier, uint256 _profitPercent) external onlyOwner {
        mlmTierProfitPercent[_mlmTier] = _profitPercent;
    }

    function repayLoan() external payable {
        require(msg.sender == borrower, "Only the borrower can repay the loan");

        uint256 repaymentAmount = calculateRepaymentAmount();
        require(msg.value == repaymentAmount, "Incorrect repayment amount");

        emit LoanRepaid(repaymentAmount);
    }

    function calculateRepaymentAmount() public view returns (uint256) {
        uint256 interest = (loanAmount * interestRate) / 100;
        return loanAmount + interest;
    }

    function withdrawProceeds() external {
        require(pendingProceeds[msg.sender] > 0, "No pending proceeds for the caller");

        uint256 amount = pendingProceeds[msg.sender];
        pendingProceeds[msg.sender] = 0;

        payable(msg.sender).transfer(amount);

        emit ProceedsWithdrawn(msg.sender, amount);
    }

    function transferLoan(address newBorrower) external onlyOwner {
        borrower = newBorrower;
        emit LoanTransfer(newBorrower);
    }

    function updateOldContractProceeds(address[] calldata addressesToUpdate, uint256[] calldata amountsToUpdate)
        external
        onlyOwner
    {
        require(addressesToUpdate.length == amountsToUpdate.length, "Array lengths mismatch");

        for (uint256 i = 0; i < addressesToUpdate.length; i++) {
            oldContractProceeds[addressesToUpdate[i]].push(Transaction(amountsToUpdate[i], block.timestamp));
        }
    }

    function updatePendingProceeds(address[] calldata addressesToUpdate, uint256[] calldata amountsToUpdate)
        external
        onlyOwner
    {
        require(addressesToUpdate.length == amountsToUpdate.length, "Array lengths mismatch");

        for (uint256 i = 0; i < addressesToUpdate.length; i++) {
            pendingProceeds[addressesToUpdate[i]] = amountsToUpdate[i];
        }
    }

    function getOldContractProceeds(address recipient) external view returns (Transaction[] memory) {
        return oldContractProceeds[recipient];
    }

    function getPendingProceeds(address recipient) external view returns (uint256) {
        return pendingProceeds[recipient];
    }

    function calculateProfit(uint256 amount, uint256 profitPercentBeforeEpoch, uint256 profitPercentAfterEpoch)
        internal
        pure
        returns (uint256)
    {
        uint256 profit = (amount * profitPercentBeforeEpoch) / 100;

        if (profitPercentAfterEpoch > profitPercentBeforeEpoch) {
            profit += ((amount - profit) * (profitPercentAfterEpoch - profitPercentBeforeEpoch)) / 100;
        }

        return profit;
    }

    function distributeProfit(uint256 amount) internal {
        uint256 weChargProfit = calculateProfit(amount, weChargProfitPercentBeforeEpoch, weChargProfitPercentAfterEpoch);
        pendingProceeds[weChargAddress] += weChargProfit;

        uint256 chargingStationOwnerProfit =
            calculateProfit(amount, chargingStationOwnerProfitPercentBeforeEpoch, chargingStationOwnerProfitPercentAfterEpoch);
        pendingProceeds[chargingStationOwnerAddress] += chargingStationOwnerProfit;

        uint256 landOwnerProfit = calculateProfit(amount, landOwnerProfitPercentBeforeEpoch, landOwnerProfitPercentAfterEpoch);
        pendingProceeds[owner] += landOwnerProfit;

        for (uint256 i = 0; i < numMLMTiers; i++) {
            address mlmTier = mlmTiers[i];
            uint256 mlmTierProfitPercent = mlmTierProfitPercent[mlmTier];
            uint256 mlmProfit = calculateProfit(amount, mlmTierProfitPercent, mlmTierProfitPercent);
            pendingProceeds[mlmTier] += mlmProfit;
        }
    }

    function receivePayment() external payable {
        distributeProfit(msg.value);
    }
}
