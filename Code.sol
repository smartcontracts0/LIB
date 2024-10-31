// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
// Updated 14/09
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract Registration {
    address public regulatoryAuthority;
    enum ActorType {RegulatoryAuthority, Manufacturer, RMsupplier, Collector, Distributor, Retailer}
    struct Actor {
        string name;
        address ethAddress;
        ActorType actorType;
        bool isRegistered;
    }

    struct RecyclingFacility {
        string name;
        address ethAddress;
        bool isRegistered;
        bool Hydro;
        bool Pyro;
        bool Mechanical;
        bool Direct;
    }
    mapping(address => Actor) public actors;
    mapping(address => RecyclingFacility) public recyclingFacilities;

    event ActorRegistered(string name, address indexed ethAddress, ActorType actorType);
    event RecyclingFacilityRegistered(string name, address indexed ethAddress, bool Hydro, bool Pyro, bool Mechanical, bool Direct);

    modifier onlyRegulatoryAuthority() {
        require(msg.sender == regulatoryAuthority, "Only regulatory authority can perform this action");
        _;
    }

    constructor() {
        regulatoryAuthority = msg.sender;
    }

    function registerRecyclingFacility(string memory _name, address _ethAddress, bool _Hydro, bool _Pyro, bool _Mechanical, bool _Direct) external onlyRegulatoryAuthority {
        require(_ethAddress != address(0), "Invalid actor address");
        require(!actors[_ethAddress].isRegistered, "This actor has already been registered");

        recyclingFacilities[_ethAddress] = RecyclingFacility({
            name: _name,
            ethAddress: _ethAddress,
            isRegistered: true,
            Hydro: _Hydro,
            Pyro: _Pyro,
            Mechanical: _Mechanical,
            Direct: _Direct
        });

        emit RecyclingFacilityRegistered(_name, _ethAddress, _Hydro, _Pyro, _Mechanical, _Direct);
    }

    function registerActor(string memory _name, address _ethAddress, ActorType _actorType) external onlyRegulatoryAuthority {
        require(_ethAddress != address(0), "Invalid actor address");
        require(!actors[_ethAddress].isRegistered, "This actor has already been registered");

        actors[_ethAddress] = Actor({
            name: _name,
            ethAddress: _ethAddress,
            actorType: _actorType,
            isRegistered: true
        });

        emit ActorRegistered(_name, _ethAddress, _actorType);
    }

    function getActor(address _ethAddress) public view returns (ActorType, bool) {
        Actor storage actor = actors[_ethAddress];
        return (actor.actorType, actor.isRegistered);
    }

    function getRecyclingFacility(address _ethAddress) public view returns (RecyclingFacility memory) {
        require(recyclingFacilities[_ethAddress].isRegistered, "Recycling facility is not registered");
        return recyclingFacilities[_ethAddress];
    }
}


contract Manufacturing {
    address public regulatoryAuthority;
    BatteryNFTContract public batteryNFTContract;
    Registration public registration;
    
    uint256 public lastSerialNumber;
    mapping(uint256 => bool) public batteryProductionStatus;
    mapping(uint256 => uint256) public batterySerialNumbers;
    
    
    event BatteryProduced(uint256 indexed batchNumber, uint256 indexed serialNumber, BatteryNFTContract.BatteryType batteryType);
    
    modifier onlyRegulatoryAuthority() {
        require(msg.sender == regulatoryAuthority, "Only regulatory authority can perform this action");
        _;
    }
    
    modifier onlyRegisteredManufacturer() {
        (Registration.ActorType actorType, bool isRegistered) = registration.getActor(msg.sender);
        require(isRegistered, "Actor is not registered");
        require(actorType == Registration.ActorType.Manufacturer, "Only manufacturers can produce batteries");
        _;
    }
    modifier onlyRegisteredCollector() {
        (Registration.ActorType actorType, bool isRegistered) = registration.getActor(msg.sender);
        require(isRegistered, "Actor is not registered");
        require(actorType == Registration.ActorType.Collector, "Only manufacturers can produce batteries");
        _;
    }
    
    constructor(address _batteryNFTContract, address _registrationContract) {
        regulatoryAuthority = msg.sender;
        batteryNFTContract = BatteryNFTContract(_batteryNFTContract);
        registration = Registration(_registrationContract);
    }
    
    function ProduceBattery(BatteryNFTContract.BatteryType _batteryType, uint256 _batchNumber) external onlyRegisteredManufacturer {
        lastSerialNumber++;
        uint256 serialNumber = lastSerialNumber;
        batteryProductionStatus[serialNumber] = true;
        batterySerialNumbers[serialNumber] = _batchNumber;

        emit BatteryProduced(_batchNumber, serialNumber, _batteryType);
        
        // Mint new NFT for the battery
        batteryNFTContract.mint(msg.sender, serialNumber, _batteryType);
    }
}


contract Collection {
    Registration public registration;
    BatteryNFTContract public batteryNFTContract;

    enum BatteryState { ToBeCollected, ToBeInspected }

    struct Battery {
        uint256 serialNumber;
        BatteryState state;
        bool hasNFT;
    }

    mapping(uint256 => Battery) public batteries; // Maps serial number to Battery struct
    uint256[] public batteryList; // List of all battery serial numbers

    event BatteryListed(uint256 indexed serialNumber, BatteryState state, bool hasNFT);
    event BatteryCollected(uint256 indexed serialNumber, address indexed collector);

    constructor(address _registrationContract, address _batteryNFTContract) {
        registration = Registration(_registrationContract);
        batteryNFTContract = BatteryNFTContract(_batteryNFTContract);
    }

    modifier onlyRegisteredCollectionCenter() {
        (Registration.ActorType actorType, bool isRegistered) = registration.getActor(msg.sender);
        require(isRegistered, "Actor is not registered");
        require(actorType == Registration.ActorType.Collector, "Only registered collection centers can collect batteries");
        _;
    }

    function collectBattery(uint256 _serialNumber, bool _hasNFT) external {
        BatteryState state = _hasNFT ? BatteryState.ToBeCollected : BatteryState.ToBeInspected;
        batteries[_serialNumber] = Battery({
            serialNumber: _serialNumber,
            state: state,
            hasNFT: _hasNFT
        });
        batteryList.push(_serialNumber);
        emit BatteryListed(_serialNumber, state, _hasNFT);
    }

    function acquireBattery(uint256 _serialNumber) external onlyRegisteredCollectionCenter {
        Battery storage battery = batteries[_serialNumber];
        require(battery.serialNumber != 0, "Battery not listed");
        require(battery.state == BatteryState.ToBeCollected || battery.state == BatteryState.ToBeInspected, "Battery is not available for collection");

        if (battery.hasNFT) {
            address currentOwner = batteryNFTContract.ownerOf(_serialNumber);
            batteryNFTContract.safeTransferFrom(currentOwner, msg.sender, _serialNumber);
            // batteryNFTContract.updateTransactionHistory(_serialNumber, string(abi.encodePacked("Collected by ", toString(msg.sender))));
        }
        
        battery.state = BatteryState(0); // Mark as collected
        emit BatteryCollected(_serialNumber, msg.sender);
    }

    function toString(address account) internal pure returns (string memory) {
        return toString(abi.encodePacked(account));
    }

    function toString(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint(uint8(data[i] >> 4))];
            str[3 + i * 2] = alphabet[uint(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }

    
}


contract Inspection {
    address public owner;
    BatteryNFTContract public batteryNFTContract;
    Registration public registration;
    uint256 public batteryHealthLimit;

    event BatteryInspectedAndMinted(uint256 indexed serialNumber, address indexed inspector, BatteryNFTContract.BatteryType batteryType);
    //event BatteryHealthChecked(uint256 indexed serialNumber, uint256 batteryHealth, BatteryNFTContract.BatteryState newState);
    event BatteryChangedToSLB(uint256 indexed serialNumber, uint256 batteryHealth, BatteryNFTContract.BatteryState newState);  // New event for SLB
    event BatteryChangedToToRecycle(uint256 indexed serialNumber, uint256 batteryHealth, BatteryNFTContract.BatteryState newState);  // New event for ToRecycle

    constructor(address _batteryNFTContract, address _registrationContract, uint256 _batteryHealthLimit) {
        owner = msg.sender;
        batteryNFTContract = BatteryNFTContract(_batteryNFTContract);
        registration = Registration(_registrationContract);
        batteryHealthLimit = _batteryHealthLimit;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only contract owner can perform this action");
        _;
    }

    modifier onlyRegisteredCollector() {
        (Registration.ActorType actorType, bool isRegistered) = registration.getActor(msg.sender);
        require(isRegistered, "Actor is not registered");
        require(actorType == Registration.ActorType.Collector, "Only Collector can change batteries");
        _;
    }

    // Update the battery state based on health value
    function InspectHealth(uint256 _serialNumber, uint256 _batteryHealth) external onlyRegisteredCollector {
        BatteryNFTContract.BatteryState newState;
        if (_batteryHealth >= batteryHealthLimit) {
            newState = BatteryNFTContract.BatteryState.SLB;
            emit BatteryChangedToSLB(_serialNumber, _batteryHealth, newState);  // Emit SLB event
        } else {
            newState = BatteryNFTContract.BatteryState.ToRecycle;
            emit BatteryChangedToToRecycle(_serialNumber, _batteryHealth, newState);  // Emit ToRecycle event
        }

        batteryNFTContract.updateBatteryState(_serialNumber, newState);

        //emit BatteryHealthChecked(_serialNumber, _batteryHealth, newState);
    }

    // Update battery to SLB
    function updateToSLB(uint256 _serialNumber) external onlyRegisteredCollector {
        batteryNFTContract.updateBatteryState(_serialNumber, BatteryNFTContract.BatteryState.SLB);
        //emit BatteryChangedToSLB(_serialNumber, _batteryHealth, newState);  // Emit SLB event
    }

    // Update battery to ToRecycle
    function updateToRecycle(uint256 _serialNumber) external onlyRegisteredCollector {
        batteryNFTContract.updateBatteryState(_serialNumber, BatteryNFTContract.BatteryState.ToRecycle);
        //emit BatteryChangedToToRecycle(_serialNumber, _batteryHealth, newState);  // Emit ToRecycle event
    }

    function inspecttype(address _owner, uint256 _serialNumber, BatteryNFTContract.BatteryType _batteryType, bool _recycle) external onlyRegisteredCollector {
        batteryNFTContract.mint(_owner, _serialNumber, _batteryType);
        
        if (_recycle == true) {
            batteryNFTContract.updateBatteryState(_serialNumber, BatteryNFTContract.BatteryState.ToRecycle);
            //emit BatteryChangedToToRecycle(_serialNumber, msg.sender);  // Emit ToRecycle event
        } else {
            batteryNFTContract.updateBatteryState(_serialNumber, BatteryNFTContract.BatteryState.SLB);
            //emit BatteryChangedToSLB(_serialNumber, msg.sender);  // Emit SLB event
        }

        emit BatteryInspectedAndMinted(_serialNumber, msg.sender, _batteryType);
    }

    // Allow the contract owner to update the battery health limit
    function setBatteryHealthLimit(uint256 _newLimit) external onlyOwner {
        batteryHealthLimit = _newLimit;
    }
}


contract Recycling {
    Registration public registration;
    BatteryNFTContract public batteryNFTContract;
    RawMaterialNFTContract public rawMaterialNFTContract;

    struct Application {
        uint256 serialNumber;
        address facilityAddress;
    }

    mapping(uint256 => Application) public applications;
    mapping(uint256 => bool) public isBatteryAssigned;

    event BatteryAssigned(uint256 indexed serialNumber, address indexed facilityAddress, BatteryNFTContract.BatteryType batteryType);
    event ApplicationSubmitted(uint256 indexed serialNumber, address indexed facilityAddress);
    event BatteryRecycled(uint256 indexed serialNumber, address indexed facilityAddress, BatteryNFTContract.BatteryType batteryType, uint256 liAmount,uint256 niAmount, uint256 coAmount);
    constructor(address _registrationContract, address _batteryNFTContract, address _rawMaterialNFTContract) {
        registration = Registration(_registrationContract);
        batteryNFTContract = BatteryNFTContract(_batteryNFTContract);
        rawMaterialNFTContract = RawMaterialNFTContract(_rawMaterialNFTContract);
    }

    function BatteryAssignment(uint256 _serialNumber) external {
        Registration.RecyclingFacility memory facility = registration.getRecyclingFacility(msg.sender);
        require(facility.isRegistered, "Only registered recycling facilities can apply");
        
        BatteryNFTContract.Battery memory battery = batteryNFTContract.getBattery(_serialNumber);
        require(!isBatteryAssigned[_serialNumber], "Battery is already assigned for recycling");
        require(battery.state == BatteryNFTContract.BatteryState.ToRecycle, "Battery must be in To Recycle state");
        
        if (
            (battery.batteryType == BatteryNFTContract.BatteryType.LFO && (facility.Hydro || facility.Pyro || facility.Mechanical)) ||
            (battery.batteryType == BatteryNFTContract.BatteryType.LCO && (facility.Hydro || facility.Pyro || facility.Mechanical)) ||
            (battery.batteryType == BatteryNFTContract.BatteryType.LMO && (facility.Pyro || facility.Mechanical)) ||
            (battery.batteryType == BatteryNFTContract.BatteryType.NMC && facility.Direct)
        ) {
            applications[_serialNumber] = Application({
                serialNumber: _serialNumber,
                facilityAddress: msg.sender
            });

            isBatteryAssigned[_serialNumber] = true;
            emit ApplicationSubmitted(_serialNumber, msg.sender);
            emit BatteryAssigned(_serialNumber, msg.sender, battery.batteryType);
        } else {
            revert("Facility does not meet the recycling conditions for this battery type");
        }
    }

    function recycleBattery(uint256 _serialNumber, uint256 _liAmount, uint256 _niAmount, uint256 _coAmount) external {
        Application memory application = applications[_serialNumber];
        require(application.facilityAddress == msg.sender, "Only the assigned recycling facility can recycle this battery");

        BatteryNFTContract.Battery memory battery = batteryNFTContract.getBattery(_serialNumber);
        require(battery.state == BatteryNFTContract.BatteryState.ToRecycle, "Battery must be in ToRecycle state");

        // Update battery state to Recycled
        batteryNFTContract.updateBatteryState(_serialNumber, BatteryNFTContract.BatteryState.Recycled);

        // Mint raw materials as recycled
        rawMaterialNFTContract.mint(msg.sender, rawMaterialNFTContract.lastSerialNumber() + 1, RawMaterialNFTContract.MaterialType.Li, RawMaterialNFTContract.MaterialState.Recycled, _liAmount);
        rawMaterialNFTContract.mint(msg.sender, rawMaterialNFTContract.lastSerialNumber() + 2, RawMaterialNFTContract.MaterialType.Ni, RawMaterialNFTContract.MaterialState.Recycled, _niAmount);
        rawMaterialNFTContract.mint(msg.sender, rawMaterialNFTContract.lastSerialNumber() + 3, RawMaterialNFTContract.MaterialType.Co, RawMaterialNFTContract.MaterialState.Recycled, _coAmount);

         emit BatteryRecycled(_serialNumber, msg.sender, battery.batteryType, _liAmount, _niAmount, _coAmount);
    }    

    function getApplication(uint256 _serialNumber) public view returns (Application memory) {
        return applications[_serialNumber];
    }
}


contract Trade {
    Registration public registration;
    BatteryNFTContract public batteryNFTContract;
    RawMaterialNFTContract public rawMaterialNFTContract;

    struct Listing {
        address seller;
        uint256 price;
        bool isBattery;
        bool active;
    }

    mapping(uint256 => Listing) public listings; // Maps token ID to Listing

    event BatteryListed(uint256 indexed serialNumber, address indexed seller, uint256 price);
    event RawMaterialListed(uint256 indexed serialNumber, address indexed seller, uint256 price);
    event BatteryTransferred(uint256 indexed serialNumber, address indexed from, address indexed to);
    event RawMaterialTransferred(uint256 indexed serialNumber, address indexed from, address indexed to);
    event BatteryPurchased(uint256 indexed serialNumber, address indexed seller, address indexed buyer, uint256 price);
    event RawMaterialPurchased(uint256 indexed serialNumber, address indexed seller, address indexed buyer, uint256 price);

    constructor(address _registrationContract, address _batteryNFTContract, address _rawMaterialNFTContract) {
        registration = Registration(_registrationContract);
        batteryNFTContract = BatteryNFTContract(_batteryNFTContract);
        rawMaterialNFTContract = RawMaterialNFTContract(_rawMaterialNFTContract);
    }

    modifier onlyRegisteredActor() {
        (, bool isRegistered) = registration.getActor(msg.sender);
        require(isRegistered, "Actor is not registered");
        _;
    }

    function listBattery(uint256 _serialNumber, uint256 _price) external onlyRegisteredActor {
        require(batteryNFTContract.ownerOf(_serialNumber) == msg.sender, "Only the owner can list the battery for sale");

        listings[_serialNumber] = Listing({
            seller: msg.sender,
            price: _price * 1 ether,
            isBattery: true,
            active: true
        });

        emit BatteryListed(_serialNumber, msg.sender, _price * 1 ether);
    }

    function listRawMaterial(uint256 _serialNumber, uint256 _price) external onlyRegisteredActor {
        require(rawMaterialNFTContract.ownerOf(_serialNumber) == msg.sender, "Only the owner can list the raw material for sale");

        listings[_serialNumber] = Listing({
            seller: msg.sender,
            price: _price * 1 ether,
            isBattery: false,
            active: true
        });

        emit RawMaterialListed(_serialNumber, msg.sender, _price * 1 ether);
    }

    function purchaseBattery(uint256 _serialNumber) external payable onlyRegisteredActor {
        Listing memory listing = listings[_serialNumber];
        require(listing.active, "Listing is not active");
        require(listing.isBattery, "This is not a battery listing");
        require(msg.value >= listing.price, "Insufficient payment");

        address seller = listing.seller;
        require(batteryNFTContract.getApproved(_serialNumber) == address(this) || batteryNFTContract.isApprovedForAll(seller, address(this)), "ERC721InsufficientApproval");

        batteryNFTContract.safeTransferFrom(seller, msg.sender, _serialNumber);
        require(batteryNFTContract.ownerOf(_serialNumber) == msg.sender, "Transfer failed");
        // batteryNFTContract.updateTransactionHistory(_serialNumber, string(abi.encodePacked("Purchased from ", toString(seller), " by ", toString(msg.sender))));

        payable(seller).transfer(listing.price);
        listings[_serialNumber].active = false;

        emit BatteryPurchased(_serialNumber, seller, msg.sender, listing.price);
    }

    function purchaseRawMaterial(uint256 _serialNumber) external payable onlyRegisteredActor {
        Listing memory listing = listings[_serialNumber];
        require(listing.active, "Listing is not active");
        require(!listing.isBattery, "This is not a raw material listing");
        require(msg.value == listing.price, "Insufficient payment");

        address seller = listing.seller;
        require(rawMaterialNFTContract.getApproved(_serialNumber) == address(this) || rawMaterialNFTContract.isApprovedForAll(seller, address(this)), "ERC721InsufficientApproval");

        rawMaterialNFTContract.safeTransferFrom(seller, msg.sender, _serialNumber);
        require(rawMaterialNFTContract.ownerOf(_serialNumber) == msg.sender, "Transfer failed");
        // rawMaterialNFTContract.updateTransactionHistory(_serialNumber, string(abi.encodePacked("Purchased from ", toString(seller), " by ", toString(msg.sender))));

        payable(seller).transfer(listing.price);
        listings[_serialNumber].active = false;

        emit RawMaterialPurchased(_serialNumber, seller, msg.sender, listing.price);
    }

    function toString(address account) internal pure returns(string memory) {
        return toString(abi.encodePacked(account));
    }

    function toString(bytes memory data) internal pure returns(string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < data.length; i++) {
            str[2+i*2] = alphabet[uint(uint8(data[i] >> 4))];
            str[3+i*2] = alphabet[uint(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }
}


contract Distribution {
    Registration public registration;
    BatteryNFTContract public batteryNFTContract;
    RawMaterialNFTContract public rawMaterialNFTContract;

    event BatteryDelivered(uint256 indexed serialNumber, address indexed from, address indexed to);
    event RawMaterialDelivered(uint256 indexed serialNumber, address indexed from, address indexed to);
    event DeliveryStarted(uint256 indexed serialNumber, address indexed from, address indexed to);
    event DeliveryReceived(uint256 indexed serialNumber, address indexed to);

    mapping(uint256 => address) public deliveryStatus; // Tracks ongoing deliveries

    constructor(address _registrationContract, address _batteryNFTContract, address _rawMaterialNFTContract) {
        registration = Registration(_registrationContract);
        batteryNFTContract = BatteryNFTContract(_batteryNFTContract);
        rawMaterialNFTContract = RawMaterialNFTContract(_rawMaterialNFTContract);
    }

    modifier onlyRegisteredDistributor() {
        (Registration.ActorType actorType, bool isRegistered) = registration.getActor(msg.sender);
        require(isRegistered, "Actor is not registered");
        require(actorType == Registration.ActorType.Distributor, "Only registered distributors can deliver batteries and raw materials");
        _;
    }

    modifier onlyRegisteredRecipient(address _to) {
        (Registration.ActorType actorType, bool isRegistered) = registration.getActor(_to);
        require(isRegistered, "Recipient is not registered");
        _;
    }

    modifier onlyRecipient(uint256 _serialNumber) {
        require(deliveryStatus[_serialNumber] == msg.sender, "Only the designated recipient can confirm delivery");
        _;
    }

    function startBatteryDelivery(uint256 _serialNumber, address _to) external onlyRegisteredDistributor onlyRegisteredRecipient(_to) {
       
        require(batteryNFTContract.ownerOf(_serialNumber) == _to, "Only the owner can start the battery delivery");
        deliveryStatus[_serialNumber] = _to;

        emit DeliveryStarted(_serialNumber, msg.sender, _to);
    }

    function confirmBatteryReceiving(uint256 _serialNumber) external onlyRecipient(_serialNumber) {
        require(batteryNFTContract.ownerOf(_serialNumber) == msg.sender, "Only the owner can start the battery delivery");
        address recipient = deliveryStatus[_serialNumber];
        require(recipient != address(0), "No delivery in progress for this serial number");

        address currentOwner = batteryNFTContract.ownerOf(_serialNumber);
        // batteryNFTContract.safeTransferFrom(currentOwner, recipient, _serialNumber);
        // batteryNFTContract.updateTransactionHistory(_serialNumber, string(abi.encodePacked("Delivered from ", toString(currentOwner), " to ", toString(recipient))));

        emit BatteryDelivered(_serialNumber, currentOwner, recipient);

        delete deliveryStatus[_serialNumber]; // Clear delivery status
    }

    function startRawMaterialDelivery(uint256 _serialNumber, address _to) external onlyRegisteredDistributor onlyRegisteredRecipient(_to) {
        require(rawMaterialNFTContract.ownerOf(_serialNumber) == _to, "Only the owner can start the raw material delivery");
        
        deliveryStatus[_serialNumber] = _to;

        emit DeliveryStarted(_serialNumber, msg.sender, _to);
    }

    function confirmRawMaterialReceiving(uint256 _serialNumber) external onlyRecipient(_serialNumber) {
        require(rawMaterialNFTContract.ownerOf(_serialNumber) == msg.sender, "Only the owner can start the raw material delivery");
        address recipient = deliveryStatus[_serialNumber];
        require(recipient != address(0), "No delivery in progress for this serial number");

        address currentOwner = rawMaterialNFTContract.ownerOf(_serialNumber);
        // rawMaterialNFTContract.safeTransferFrom(currentOwner, recipient, _serialNumber);
        // rawMaterialNFTContract.updateTransactionHistory(_serialNumber, string(abi.encodePacked("Delivered from ", toString(currentOwner), " to ", toString(recipient))));

        emit RawMaterialDelivered(_serialNumber, currentOwner, recipient);

        delete deliveryStatus[_serialNumber]; // Clear delivery status
    }

    function toString(address account) internal pure returns(string memory) {
        return toString(abi.encodePacked(account));
    }

    function toString(bytes memory data) internal pure returns(string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < data.length; i++) {
            str[2+i*2] = alphabet[uint(uint8(data[i] >> 4))];
            str[3+i*2] = alphabet[uint(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }
}


contract RawMaterialNFTContract is ERC721 {
    enum MaterialType { Li, Ni, Co }
    enum MaterialState { Virgin, Recycled }

    struct RawMaterial {
        address manufacturer;
        uint256 serialNumber;
        MaterialType materialType;
        MaterialState state;
        string transactionHistory;
        uint256 amount; 
    }

    address public owner;
    Registration public registration;
    uint256 public lastSerialNumber;
    mapping(uint256 => RawMaterial) public rawMaterials;
    mapping(uint256 => bool) public mintedTokens;

    constructor(address _registrationContract) ERC721("RawMaterial", "RM") {
        owner = msg.sender;
        registration = Registration(_registrationContract);
        lastSerialNumber = 0;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only contract owner can perform this action");
        _;
    }

    modifier onlyRegisteredRMSupplier() {
        (Registration.ActorType actorType, bool isRegistered) = registration.getActor(msg.sender);
        require(isRegistered, "Actor is not registered");
        require(actorType == Registration.ActorType.RMsupplier, "Only registered RMsuppliers can mint raw materials");
        _;
    }
    //  onlyRegisteredRMSupplier
    function mint(address _to, uint256 _serialNumber, MaterialType _materialType, MaterialState _materialState, uint256 _amount) external {
        require(!mintedTokens[_serialNumber], "Token already minted");
        _mint(_to, _serialNumber);
        rawMaterials[_serialNumber] = RawMaterial({
            manufacturer: _to,
            serialNumber: _serialNumber,
            materialType: _materialType,
            state: _materialState,
            transactionHistory: "",
            amount: _amount
        });
        mintedTokens[_serialNumber] = true;
        lastSerialNumber = _serialNumber;
    }

    function updateMaterialState(uint256 _serialNumber, MaterialState _newState) external onlyOwner {
        require(mintedTokens[_serialNumber], "Token not minted");
        rawMaterials[_serialNumber].state = _newState;
    }

    function updateTransactionHistory(uint256 _serialNumber, string memory _transaction) external {
        require(ownerOf(_serialNumber) == msg.sender, "Only owner can update transaction history");
        rawMaterials[_serialNumber].transactionHistory = _transaction;
    }

    function getRawMaterial(uint256 _serialNumber) external view returns (RawMaterial memory) {
        return rawMaterials[_serialNumber];
    }
}


contract BatteryNFTContract is ERC721 {

    enum BatteryType {LFO, LCO, LMO, NMC}
    enum BatteryState {New, ToBeCollected, ToBeInspected, SLB, ToRecycle, Recycled}

    struct Battery {
        address manufacturer;
        uint256 serialNumber;
        BatteryType batteryType;
        BatteryState state; 
        string transactionHistory;
    }

    address public owner;
    uint256 public lastSerialNumber;
    mapping(uint256 => Battery) public batteries;
    mapping(uint256 => bool) public mintedTokens;

    constructor() ERC721("Battery", "BATT") {
        owner = msg.sender;
        lastSerialNumber = 0;
    }

    // modifier onlyOwner() {
    //     require(msg.sender == owner, "Only contract owner can perform this action");
    //     _;
    // }

    // onlyOwner
    function mint(address _to, uint256 _serialNumber, BatteryType _batteryType) external {
        require(!mintedTokens[_serialNumber], "Token already minted");
        _mint(_to, _serialNumber);
        batteries[_serialNumber] = Battery({
            manufacturer: _to,
            serialNumber: _serialNumber,
            batteryType: _batteryType,
            state: BatteryState.New,
            transactionHistory: ""
        });
        mintedTokens[_serialNumber] = true;
        lastSerialNumber = _serialNumber;
    }
    // onlyOwner
    function updateBatteryState(uint256 _serialNumber, BatteryState _newState) external  {
        require(mintedTokens[_serialNumber], "Token not minted");
        batteries[_serialNumber].state = _newState;
    }
    function updateTransactionHistory(uint256 _serialNumber, string memory _transaction) external {
        require(ownerOf(_serialNumber) == msg.sender, "Only owner can update transaction history");
        batteries[_serialNumber].transactionHistory = _transaction;
    }
        function getBattery(uint256 _serialNumber) external view returns (Battery memory) {
        return batteries[_serialNumber];
    }
}

