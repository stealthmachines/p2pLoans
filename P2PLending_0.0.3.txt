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

    constructor(address _chgControlAddress) {
        chgControl = CHGControl(_chgControlAddress);
        chgControlAddress = _chgControlAddress;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the contract owner can call this function");
        _;
    }

    modifier onlyBorrower() {
        require(msg.sender == borrower, "Only the borrower can call this function");
        _;
    }

    modifier onlyLender() {
        require(msg.sender == lender, "Only the lender can call this function");
        _;
    }

    function initialize(
        string memory _assetType,
        string memory _assetID,
        uint _value,
        uint _loanAmount,
        uint _interestRate,
        uint _termLength,
        address _borrower,
        address payable _lender,
        address _weChargAddress,
        address _chargingStationOwnerAddress,
        uint _weChargProfitPercentBeforeEpoch,
        uint _chargingStationOwnerProfitPercentBeforeEpoch,
        uint _weChargProfitPercentAfterEpoch,
        uint _chargingStationOwnerProfitPercentAfterEpoch,
        uint _landOwnerProfitPercentBeforeEpoch,
        uint _landOwnerProfitPercentAfterEpoch,
        uint _numMLMTiers
    ) external onlyOwner {
        collateral = Collateral({
            assetType: _assetType,
            assetID: _assetID,
            value: _value
        });

        loanAmount = _loanAmount;
        interestRate = _interestRate;
        termLength = _termLength;
        borrower = _borrower;
        lender = _lender;
        weChargAddress = _weChargAddress;
        chargingStationOwnerAddress = _chargingStationOwnerAddress;
        weChargProfitPercentBeforeEpoch = _weChargProfitPercentBeforeEpoch;
        chargingStationOwnerProfitPercentBeforeEpoch = _chargingStationOwnerProfitPercentBeforeEpoch;
        weChargProfitPercentAfterEpoch = _weChargProfitPercentAfterEpoch;
        chargingStationOwnerProfitPercentAfterEpoch = _chargingStationOwnerProfitPercentAfterEpoch;
        landOwnerProfitPercentBeforeEpoch = _landOwnerProfitPercentBeforeEpoch;
        landOwnerProfitPercentAfterEpoch = _landOwnerProfitPercentAfterEpoch;
        numMLMTiers = _numMLMTiers;

        for (uint i = 0; i < numMLMTiers; i++) {
            mlmTiers[i] = address(0);
        }

        owner = msg.sender;
        loanActive = true;
    }

    function approveLoan() external onlyBorrower {
        borrowerApproval[msg.sender] = true;
    }

    function approveRepayment() external onlyLender {
        lenderApproval[msg.sender] = true;
    }

    function calculateInterest() public view returns (uint) {
        if (interestRate == 0) {
            return 0;
        }
        uint interest = loanAmount * interestRate / 100;
        return interest;
    }

    function calculatePenalty(uint daysLate) public view returns (uint) {
        // Implement your penalty calculation logic here
        // For example, you could charge a fixed amount per day late or a percentage of the remaining balance.
        // This function should return the calculated penalty amount.
        // Please note that this is just a placeholder function, and you should modify it based on your specific requirements.
        // The example below charges a penalty of 1% of the remaining balance per day late.
        uint remainingBalance = loanAmount - unpaidBalance;
        uint penaltyRate = getPenaltyRate();
        uint penalty = remainingBalance * penaltyRate / 100;
        uint totalPenalty = penalty * daysLate;
        return totalPenalty;
    }

    function repayLoan() external payable onlyLender {
        require(loanActive, "Loan is not active");
        require(borrowerApproval[borrower] && lenderApproval[lender], "Both borrower and lender must approve the loan");

        uint interest = calculateInterest();
        uint totalRepayment = loanAmount + interest;
        require(msg.value >= totalRepayment, "Insufficient funds to repay the loan");

        // Check if the repayment is made within the term length
        if (block.timestamp <= termLength) {
            // Loan repaid within the term, no penalty
            loanActive = false;
            unpaidBalance = 0;
            pendingProceeds[weChargAddress] += interest * weChargProfitPercentBeforeEpoch / 100;
            pendingProceeds[chargingStationOwnerAddress] += interest * chargingStationOwnerProfitPercentBeforeEpoch / 100;
            pendingProceeds[owner] += msg.value - interest - (interest * (weChargProfitPercentBeforeEpoch + chargingStationOwnerProfitPercentBeforeEpoch) / 100);
            distributeMLMProfits(msg.value);
        } else {
            // Loan repaid after the term, calculate penalty
            uint daysLate = (block.timestamp - termLength) / 1 days;
            uint penalty = calculatePenalty(daysLate);
            uint totalPayment = totalRepayment + penalty;
            require(msg.value >= totalPayment, "Insufficient funds to repay the loan with penalty");

            loanActive = false;
            unpaidBalance = 0;
            pendingProceeds[weChargAddress] += interest * weChargProfitPercentAfterEpoch / 100;
            pendingProceeds[chargingStationOwnerAddress] += interest * chargingStationOwnerProfitPercentAfterEpoch / 100;
            pendingProceeds[owner] += msg.value - interest - penalty - (interest * (weChargProfitPercentAfterEpoch + chargingStationOwnerProfitPercentAfterEpoch) / 100);
            distributeMLMProfits(msg.value);
        }

        // Store the repayment amount and timestamp
        Transaction memory transaction = Transaction({
            amount: msg.value,
            timestamp: block.timestamp
        });
        oldContractProceeds[weChargAddress].push(transaction);
    }

    function getPenaltyRate() public view returns (uint) {
        // Retrieve the penalty rate from the contract owner or another source
        // In this example, the penalty rate is a variable set by the contract owner
        // You can modify this function to retrieve the penalty rate from your desired source
        // For simplicity, we assume a fixed penalty rate of 1%
        return 1;
    }

    function withdrawProceeds() external onlyControlled {
        require(pendingProceeds[msg.sender] > 0, "No pending proceeds for the address");
        uint256 amount = pendingProceeds[msg.sender];
        pendingProceeds[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }

    function distributeMLMProfits(uint totalRepayment) internal {
        uint remainingRepayment = totalRepayment;
        uint landOwnerProfitBeforeEpoch = (totalRepayment * landOwnerProfitPercentBeforeEpoch) / 100;
        remainingRepayment -= landOwnerProfitBeforeEpoch;

        for (uint i = 0; i < numMLMTiers; i++) {
            address mlmTier = mlmTiers[i];
            if (mlmTier != address(0)) {
                uint mlmTierProfit = (totalRepayment * mlmTierProfitPercent[mlmTier]) / 100;
                remainingRepayment -= mlmTierProfit;
                pendingProceeds[mlmTier] += mlmTierProfit;
            }
        }

        uint landOwnerProfitAfterEpoch = (remainingRepayment * landOwnerProfitPercentAfterEpoch) / 100;
        pendingProceeds[owner] += landOwnerProfitBeforeEpoch + landOwnerProfitAfterEpoch;
    }

    function setMLMTierAddress(uint tierIndex, address mlmTierAddress) external onlyCHGControl {
        require(tierIndex < numMLMTiers, "Invalid MLM tier index");
        mlmTiers[tierIndex] = mlmTierAddress;
    }

    function setMLMTierProfitPercent(address mlmTierAddress, uint profitPercent) external onlyCHGControl {
        require(mlmTierAddress != address(0), "Invalid MLM tier address");
        mlmTierProfitPercent[mlmTierAddress] = profitPercent;
    }

    function updatePenaltyRate(uint newPenaltyRate) external onlyCHGControl {
        // Update the penalty rate
        // This function can be called by the contract owner or another authorized entity
        // You can modify this function to include additional validation or logic based on your specific requirements
        require(newPenaltyRate >= 0, "Invalid penalty rate");
        // Perform additional validation if needed
        // For example, restrict who can update the penalty rate or impose a maximum limit

        penaltyRate = newPenaltyRate;
    }
}
