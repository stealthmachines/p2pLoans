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
        uint256 amount;
        uint256 timestamp;
    }

    Collateral public collateral;
    address public owner;
    uint256 public loanAmount;
    uint256 public interestRate;
    uint256 public termLength;
    address public borrower;
    address payable public lender;
    bool public loanActive;
    uint256 public unpaidBalance;
    mapping(address => bool) public borrowerApproval;
    mapping(address => bool) public lenderApproval;
    address public weChargAddress;
    address public chargingStationOwnerAddress;
    uint256 public weChargProfitPercentBeforeEpoch; // Profit percent for WeCharg before epoch
    uint256 public chargingStationOwnerProfitPercentBeforeEpoch; // Profit percent for charging station owner before epoch
    uint256 public weChargProfitPercentAfterEpoch; // Profit percent for WeCharg after epoch
    uint256 public chargingStationOwnerProfitPercentAfterEpoch; // Profit percent for charging station owner after epoch
    uint256 public landOwnerProfitPercentBeforeEpoch; // Profit percent for land owner before epoch
    uint256 public landOwnerProfitPercentAfterEpoch; // Profit percent for land owner after epoch
    uint256 public numMLMTiers; // Number of MLM tiers
    mapping (uint256 => address) public mlmTiers; // Mapping of MLM tier index to address
    mapping (address => uint256) public mlmTierProfitPercent; // Profit percent for each MLM tier

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
        owner = msg.sender;
    }

    function initiateLoan(
        uint256 _loanAmount,
        uint256 _interestRate,
        uint256 _termLength,
        address _borrower,
        string memory _assetType,
        string memory _assetID,
        uint256 _assetValue
    ) external onlyCHGControl {
        require(!loanActive, "Loan already active");

        collateral = Collateral({
            assetType: _assetType,
            assetID: _assetID,
            value: _assetValue
        });

        loanAmount = _loanAmount;
        interestRate = _interestRate;
        termLength = _termLength;
        borrower = _borrower;
        loanActive = true;
    }

    function approveLoan() external onlyCHGControl {
        require(loanActive, "No active loan to approve");
        borrowerApproval[msg.sender] = true;
    }

    function approveLoanByLender() external {
        require(loanActive, "No active loan to approve");
        lenderApproval[msg.sender] = true;
    }

    function deposit() external payable {
        require(msg.sender == borrower, "Only the borrower can deposit funds");
        require(loanActive, "No active loan");
        require(borrowerApproval[msg.sender], "Borrower approval required");
        require(lenderApproval[lender], "Lender approval required");

        uint256 depositAmount = msg.value;
        unpaidBalance += depositAmount;

        if (unpaidBalance >= loanAmount) {
            // Loan fully funded
            uint256 excessAmount = unpaidBalance - loanAmount;
            if (excessAmount > 0) {
                // Return excess amount to borrower
                (bool success, ) = borrower.call{value: excessAmount}("");
                require(success, "Failed to return excess funds to borrower");
            }

            // Distribute proceeds to MLM tiers
            distributeMLMProfits();

            // Transfer loan amount to lender
            (bool success, ) = lender.call{value: loanAmount}("");
            require(success, "Failed to transfer loan amount to lender");

            loanActive = false;
        }
    }

    function repayLoan() external payable {
        require(msg.sender == borrower, "Only the borrower can repay the loan");
        require(!loanActive, "Loan is still active");
        require(msg.value == unpaidBalance, "Incorrect repayment amount");

        // Transfer repayment amount to lender
        (bool success, ) = lender.call{value: msg.value}("");
        require(success, "Failed to transfer repayment amount to lender");

        // Reset loan details
        loanAmount = 0;
        interestRate = 0;
        termLength = 0;
        borrower = address(0);
        lender = payable(address(0));
        unpaidBalance = 0;
        delete borrowerApproval[msg.sender];
        delete lenderApproval[lender];
    }

    function withdrawProceeds() external {
        uint256 proceedAmount = pendingProceeds[msg.sender];
        require(proceedAmount > 0, "No proceeds to withdraw");

        pendingProceeds[msg.sender] = 0;

        // Transfer proceeds to CHG address
        (bool success, ) = msg.sender.call{value: proceedAmount}("");
        require(success, "Failed to transfer proceeds to CHG address");
    }

    function transferLender(address payable _newLender) external onlyAgent {
        require(loanActive, "No active loan to transfer");
        lender = _newLender;
    }

    function setMLMProfitDistribution(
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
    ) external onlyAdmin {
        require(_weChargAddress != address(0), "Invalid WeCharg address");
        require(_chargingStationOwnerAddress != address(0), "Invalid charging station owner address");
        require(_numMLMTiers == _mlmTiers.length && _numMLMTiers == _mlmTierProfitPercent.length, "Invalid MLM tier details");

        weChargAddress = _weChargAddress;
        chargingStationOwnerAddress = _chargingStationOwnerAddress;
        weChargProfitPercentBeforeEpoch = _weChargProfitPercentBeforeEpoch;
        chargingStationOwnerProfitPercentBeforeEpoch = _chargingStationOwnerProfitPercentBeforeEpoch;
        weChargProfitPercentAfterEpoch = _weChargProfitPercentAfterEpoch;
        chargingStationOwnerProfitPercentAfterEpoch = _chargingStationOwnerProfitPercentAfterEpoch;
        landOwnerProfitPercentBeforeEpoch = _landOwnerProfitPercentBeforeEpoch;
        landOwnerProfitPercentAfterEpoch = _landOwnerProfitPercentAfterEpoch;
        numMLMTiers = _numMLMTiers;

        for (uint256 i = 0; i < _numMLMTiers; i++) {
            mlmTiers[i] = _mlmTiers[i];
            mlmTierProfitPercent[_mlmTiers[i]] = _mlmTierProfitPercent[i];
        }
    }

    function distributeMLMProfits() private {
        require(loanActive, "No active loan to distribute profits");

        uint256 totalProfit = calculateTotalProfit();

        // Distribute profits to MLM tiers
        for (uint256 i = 0; i < numMLMTiers; i++) {
            address mlmTier = mlmTiers[i];
            uint256 profitPercent = mlmTierProfitPercent[mlmTier];
            uint256 mlmProfit = (totalProfit * profitPercent) / 100;

            // Add profit to pending proceeds
            pendingProceeds[mlmTier] += mlmProfit;
        }
    }

    function calculateTotalProfit() private view returns (uint256) {
        require(loanActive, "No active loan to calculate profits");

        uint256 loanDuration = termLength * 1 days;
        uint256 elapsedDuration = block.timestamp - collateral.timestamp;
        uint256 remainingDuration = loanDuration - elapsedDuration;

        // Calculate profit before and after the epoch
        uint256 profitBeforeEpoch = (loanAmount * interestRate * elapsedDuration) / (100 * 365 days);
        uint256 profitAfterEpoch = (loanAmount * interestRate * remainingDuration) / (100 * 365 days);

        // Calculate total profit based on profit distribution percentages
        uint256 totalProfit = 0;

        // Profit for WeCharg before the epoch
        totalProfit += (profitBeforeEpoch * weChargProfitPercentBeforeEpoch) / 100;

        // Profit for charging station owner before the epoch
        totalProfit += (profitBeforeEpoch * chargingStationOwnerProfitPercentBeforeEpoch) / 100;

        // Profit for WeCharg after the epoch
        totalProfit += (profitAfterEpoch * weChargProfitPercentAfterEpoch) / 100;

        // Profit for charging station owner after the epoch
        totalProfit += (profitAfterEpoch * chargingStationOwnerProfitPercentAfterEpoch) / 100;

        // Profit for land owner before the epoch
        totalProfit += (profitBeforeEpoch * landOwnerProfitPercentBeforeEpoch) / 100;

        // Profit for land owner after the epoch
        totalProfit += (profitAfterEpoch * landOwnerProfitPercentAfterEpoch) / 100;

        return totalProfit;
    }
}
