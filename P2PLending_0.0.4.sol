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
        uint value;
    }

    struct Transaction {
        uint amount;
        uint timestamp;
    }

    Collateral public collateral;
    address public owner;
    uint public loanAmount;
    uint public interestRate;
    uint public termLength;
    address public borrower;
    address payable public lender;
    bool public loanActive;
    uint public unpaidBalance;
    mapping(address => bool) public borrowerApproval;
    mapping(address => bool) public lenderApproval;
    address public weChargAddress;
    address public chargingStationOwnerAddress;
    uint public weChargProfitPercentBeforeEpoch; // Profit percent for WeCharg before epoch
    uint public chargingStationOwnerProfitPercentBeforeEpoch; // Profit percent for charging station owner before epoch
    uint public weChargProfitPercentAfterEpoch; // Profit percent for WeCharg after epoch
    uint public chargingStationOwnerProfitPercentAfterEpoch; // Profit percent for charging station owner after epoch
    uint public landOwnerProfitPercentBeforeEpoch; // Profit percent for land owner before epoch
    uint public landOwnerProfitPercentAfterEpoch; // Profit percent for land owner after epoch
    uint public numMLMTiers; // Number of MLM tiers
    mapping (uint => address) public mlmTiers; // Mapping of MLM tier index to address
    mapping (address => uint) public mlmTierProfitPercent; // Profit percent for each MLM tier

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
    uint public penaltyRate; // Penalty rate

    constructor(address _chgControlAddress) {
        chgControl = CHGControl(_chgControlAddress);
        chgControlAddress = _chgControlAddress;
    }

    function setPenaltyRate(uint _penaltyRate) external onlyCHGControl {
        penaltyRate = _penaltyRate;
    }

    function initialize(
        string memory _assetType,
        string memory _assetID,
        uint _value,
        uint _loanAmount,
        uint _interestRate,
        uint _termLength,
        address _weChargAddress,
        address _chargingStationOwnerAddress,
        uint _weChargProfitPercentBeforeEpoch,
        uint _chargingStationOwnerProfitPercentBeforeEpoch,
        uint _weChargProfitPercentAfterEpoch,
        uint _chargingStationOwnerProfitPercentAfterEpoch,
        uint _landOwnerProfitPercentBeforeEpoch,
        uint _landOwnerProfitPercentAfterEpoch,
        uint _numMLMTiers
    ) external {
        collateral = Collateral(_assetType, _assetID, _value);
        owner = msg.sender;
        loanAmount = _loanAmount;
        interestRate = _interestRate;
        termLength = _termLength;
        borrower = address(0);
        lender = payable(address(0));
        loanActive = false;
        unpaidBalance = 0;
        borrowerApproval[msg.sender] = true;
        weChargAddress = _weChargAddress;
        chargingStationOwnerAddress = _chargingStationOwnerAddress;
        weChargProfitPercentBeforeEpoch = _weChargProfitPercentBeforeEpoch;
        chargingStationOwnerProfitPercentBeforeEpoch = _chargingStationOwnerProfitPercentBeforeEpoch;
        weChargProfitPercentAfterEpoch = _weChargProfitPercentAfterEpoch;
        chargingStationOwnerProfitPercentAfterEpoch = _chargingStationOwnerProfitPercentAfterEpoch;
        landOwnerProfitPercentBeforeEpoch = _landOwnerProfitPercentBeforeEpoch;
        landOwnerProfitPercentAfterEpoch = _landOwnerProfitPercentAfterEpoch;
        numMLMTiers = _numMLMTiers;
    }

    function approveLoan() external {
        require(borrowerApproval[msg.sender], "You are not authorized to approve the loan");
        borrowerApproval[msg.sender] = false;
        lenderApproval[msg.sender] = true;
        if (checkLoanApproved()) {
            loanActive = true;
            borrower = msg.sender;
            unpaidBalance = loanAmount;
        }
    }

    function approveRepayment() external {
        require(lenderApproval[msg.sender], "You are not authorized to approve the repayment");
        lenderApproval[msg.sender] = false;
        borrowerApproval[msg.sender] = true;
        if (!checkLoanApproved()) {
            loanActive = false;
            borrower = address(0);
            unpaidBalance = 0;
        }
    }

    function calculateInterest(uint daysLate) public view returns (uint) {
        uint interest = (loanAmount * interestRate * daysLate) / (365 * 100);
        return interest;
    }

    function calculatePenalty(uint daysLate) public view returns (uint) {
        uint penalty = (unpaidBalance * penaltyRate * daysLate) / (365 * 100);
        return penalty;
    }

    function repayLoan() external payable {
        require(loanActive, "No active loan to repay");
        require(msg.sender == lender, "Only the lender can repay the loan");

        uint daysLate = (block.timestamp - termLength) / (60 * 60 * 24);
        uint interest = calculateInterest(daysLate);
        uint penalty = calculatePenalty(daysLate);
        uint totalRepayment = unpaidBalance + interest + penalty;

        require(msg.value >= totalRepayment, "Insufficient repayment amount");

        // Distribute proceeds
        distributeProceeds(totalRepayment);

        // Update loan status
        loanActive = false;
        lender = payable(address(0));
        unpaidBalance = 0;

        // Return excess payment to lender
        if (msg.value > totalRepayment) {
            payable(msg.sender).transfer(msg.value - totalRepayment);
        }
    }

    function distributeProceeds(uint totalRepayment) internal {
        uint remainingAmount = totalRepayment;
        uint remainingProfitPercent = 100;

        // Distribute profits to WeCharg and charging station owner before epoch
        distributeProfitBeforeEpoch(remainingAmount, remainingProfitPercent);

        // Distribute profits to MLM tiers
        distributeProfitToMLMTiers(remainingAmount, remainingProfitPercent);

        // Distribute profits to WeCharg and charging station owner after epoch
        distributeProfitAfterEpoch(remainingAmount, remainingProfitPercent);

        // Distribute profits to land owner before epoch
        distributeProfitToLandOwnerBeforeEpoch(remainingAmount, remainingProfitPercent);

        // Distribute profits to land owner after epoch
        distributeProfitToLandOwnerAfterEpoch(remainingAmount, remainingProfitPercent);
    }

    function distributeProfitBeforeEpoch(uint totalAmount, uint remainingProfitPercent) internal {
        uint weChargProfit = (totalAmount * weChargProfitPercentBeforeEpoch) / 100;
        uint chargingStationOwnerProfit = (totalAmount * chargingStationOwnerProfitPercentBeforeEpoch) / 100;

        pendingProceeds[weChargAddress] += weChargProfit;
        pendingProceeds[chargingStationOwnerAddress] += chargingStationOwnerProfit;

        remainingProfitPercent -= weChargProfitPercentBeforeEpoch + chargingStationOwnerProfitPercentBeforeEpoch;
    }

    function distributeProfitToMLMTiers(uint totalAmount, uint remainingProfitPercent) internal {
        uint profitPercentPerTier = remainingProfitPercent / numMLMTiers;

        for (uint i = 0; i < numMLMTiers; i++) {
            address mlmTier = mlmTiers[i];
            uint mlmTierProfit = (totalAmount * profitPercentPerTier) / 100;

            pendingProceeds[mlmTier] += mlmTierProfit;
        }

        remainingProfitPercent -= profitPercentPerTier * numMLMTiers;
    }

    function distributeProfitAfterEpoch(uint totalAmount, uint remainingProfitPercent) internal {
        uint weChargProfit = (totalAmount * weChargProfitPercentAfterEpoch) / 100;
        uint chargingStationOwnerProfit = (totalAmount * chargingStationOwnerProfitPercentAfterEpoch) / 100;

        pendingProceeds[weChargAddress] += weChargProfit;
        pendingProceeds[chargingStationOwnerAddress] += chargingStationOwnerProfit;

        remainingProfitPercent -= weChargProfitPercentAfterEpoch + chargingStationOwnerProfitPercentAfterEpoch;
    }

    function distributeProfitToLandOwnerBeforeEpoch(uint totalAmount, uint remainingProfitPercent) internal {
        uint landOwnerProfit = (totalAmount * landOwnerProfitPercentBeforeEpoch) / 100;

        pendingProceeds[owner] += landOwnerProfit;

        remainingProfitPercent -= landOwnerProfitPercentBeforeEpoch;
    }

    function distributeProfitToLandOwnerAfterEpoch(uint totalAmount, uint remainingProfitPercent) internal {
        uint landOwnerProfit = (totalAmount * landOwnerProfitPercentAfterEpoch) / 100;

        pendingProceeds[owner] += landOwnerProfit;

        remainingProfitPercent -= landOwnerProfitPercentAfterEpoch;
    }

    function withdrawProceeds() external {
        uint256 amount = pendingProceeds[msg.sender];
        require(amount > 0, "No pending proceeds for the caller");

        pendingProceeds[msg.sender] = 0;
        oldContractProceeds[msg.sender].push(Transaction(amount, block.timestamp));
        payable(msg.sender).transfer(amount);
    }

    function checkLoanApproved() internal view returns (bool) {
        for (uint i = 0; i < mlmTiers.length; i++) {
            if (!lenderApproval[mlmTiers[i]]) {
                return false;
            }
        }
        return true;
    }
}
