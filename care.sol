pragma solidity ^0.4.23;

contract Ownable {
  address public owner;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  constructor() public {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  function transferOwnership(address newOwner) onlyOwner public {
    require(newOwner != address(0));
    emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }
}

contract Prices is Ownable{

    mapping (uint64 => uint64) ICDPrices;
    mapping  (address=>uint64) negoiatedPercentages;

     constructor () public {

        ICDPrices[90471] = 100;
        ICDPrices[29880] = 4500;
        ICDPrices[71260] = 475;
        ICDPrices[31295] = 1300;
        
    }

    // Methods related to ICD prices.
    //To store the sugery price
    function addPrice(uint64 CPT, uint64 price) public onlyOwner {
        ICDPrices[CPT] = price;
    }

    //To get the ICD price
    function getPrice(uint64 CPT) public view  returns(uint64) {
        return ICDPrices[CPT];
    }

    //To add a negotiation between the Hospitals and Govt
    function addNegotationPercentage (address providerAddress, uint64 percentage) public onlyOwner {
        negoiatedPercentages[providerAddress] = percentage;
    }
       
    function getNegotationPercentage(address providerAddress) public view returns(uint64) {
        return negoiatedPercentages[providerAddress];
    }
                   
    function getNegotiatedCost(uint64[] ICDs,address providerAddress) public  view returns(uint64) {
        uint64 costAfterDiscount=0;
        uint64 discountedPercent = 100-negoiatedPercentages[providerAddress];

       for(uint64 i=0; i<ICDs.length; i++){
            uint64 ICD = ICDs[i];
            costAfterDiscount = costAfterDiscount +(ICDPrices[ICD]/100)*discountedPercent;
        }

        return  costAfterDiscount;
    }  
}


contract Care is Ownable{
    
    enum Status {created,approved,Processed,rejected}  
    
   struct Patient {
       
       address patientAddress;
       uint64  maxClaimAmount;
       uint64  amountClaimed;
       uint64  numberOfClaims;
   }
   
   
   
   struct Claim {
       uint64  claimID;
       address patientAddress;
       address providerAddress;
       address createdBy;
       address stateAddress;
       uint64[] CPTIDs;
       Status  claimStatus;
       uint64  stateGovtShare;
       uint64  centralGovtShare;
   }
    
    
    Prices pricesContract;
    
    uint64 centalGovtPercentage;
    uint64 stateGovtPercentage;
    uint64 maxClaimAmountPerPatient;
    
    
    mapping(address=>Patient) patientDetails;
    
    mapping(uint64=>Claim)  claimDetails;
    
    uint64 centralGovtShareTotal;
    
    mapping(address=>uint64) stateGovtShareTotal;
    
    event PatientAdded(address indexed addedBy,address patientAddress,uint timeStamp);
    
    event ClaimCreated(address indexed stateAddress,uint claimID,address indexed patientAddress,address indexed providerAddress, uint timeStamp);
    
    event ClaimApproved(address indexed stateAddress,uint claimID,address indexed patientAddress,address indexed providerAddress, uint timeStamp);
    
   mapping(address=>bool) deskUsers;
   
   address[] deskUsersList;
   
   
   modifier onlyAuthorizedPersonal () {
       
       require(msg.sender==owner||deskUsers[msg.sender]);
       
       _;
   }
   
   function setContractAddress(address _contractAddress) public onlyOwner{
       pricesContract = Prices(_contractAddress);
   }
   
   function setValues(uint64 _centralPercent,uint64 _satePercent,uint64 _maxClaim) public onlyOwner {
       centalGovtPercentage = _centralPercent;
       stateGovtPercentage = _satePercent;
       maxClaimAmountPerPatient = _maxClaim;
   }
   
   
   function addDeskUser(address _newUserAddress) public onlyOwner {
       
       deskUsers[_newUserAddress] = true;
       deskUsersList.push(_newUserAddress);
       
   }
   
   function addPatient(address _patientAddress,uint64 _maxClaimAmount,uint64 _amountClaimed,uint64 _no) public onlyAuthorizedPersonal {
       
       Patient memory temp = Patient(_patientAddress,_maxClaimAmount,_amountClaimed,_no);
       
       patientDetails[_patientAddress] = temp;
       
       emit PatientAdded(msg.sender,_patientAddress,block.timestamp);
       
   }
   
   
   function addClaim(uint64 _claimID,address _stateAddress,address _patientAddress,address _providerAddress,uint64[] _ICDs) public onlyAuthorizedPersonal {
       
       
       require(patientDetails[_patientAddress].amountClaimed<maxClaimAmountPerPatient);
       
       Claim memory temp = Claim(_claimID,_patientAddress,_providerAddress,msg.sender,_stateAddress,_ICDs,Status.created,0,0);
       
       claimDetails[_claimID] = temp;
       
       emit ClaimCreated(_stateAddress,_claimID,_patientAddress,_providerAddress,block.timestamp);
   }
   
   function approveClaim(uint64 _claimID) public {
       
       require(msg.sender==claimDetails[_claimID].patientAddress);
       
       require(processClaim(_claimID));
       
   }
   
   
   function sendClaimForProcessing(uint64 _claimID) public onlyAuthorizedPersonal  {
       
       require(processClaim(_claimID));
   }
   
   
    function processClaim(uint64 _claimID) internal returns (bool) {
        
        Claim memory temp1 = claimDetails[_claimID];
        
        Patient memory temp2 = patientDetails[temp1.patientAddress];
        
        uint64 amount = pricesContract.getNegotiatedCost(temp1.CPTIDs,temp1.providerAddress);
        
        if(amount>(temp2.maxClaimAmount-temp2.amountClaimed)){
            
           amount = temp2.maxClaimAmount-temp2.amountClaimed;
            
        }
        
            temp1.centralGovtShare = (amount*centalGovtPercentage)/100;
            temp1.stateGovtShare   = (amount*stateGovtPercentage)/100;
            temp1.claimStatus = Status.Processed;  
            
            centralGovtShareTotal += temp1.centralGovtShare;
            stateGovtShareTotal[temp1.stateAddress]   += temp1.stateGovtShare;
            
            temp2.amountClaimed += amount;
            temp2.numberOfClaims++;
            
            claimDetails[_claimID] = temp1;
            patientDetails[temp1.patientAddress] = temp2;
            
            emit ClaimApproved(temp1.stateAddress,temp1.claimID,temp1.patientAddress,temp1.providerAddress,now);
        
        return true;
    }
    
    function getCenterTotalShare() public view returns (uint64) {
        return centralGovtShareTotal;
    }
    
    function getSateTotalShare(address _stateAddress) public view returns (uint64) {
        return stateGovtShareTotal[_stateAddress];
    }
    
    function getPatientDetails(address _patientAddress) public view returns(uint64,uint64,uint64){
        return (patientDetails[_patientAddress].maxClaimAmount,patientDetails[_patientAddress].amountClaimed,patientDetails[_patientAddress].numberOfClaims);
        
    }
    
    function getClaimDetails(uint64 _claimID) public view returns(address,address,address,address,uint64[],uint64,uint64,Status){
        Claim memory temp = claimDetails[_claimID];
        return(temp.patientAddress,temp.providerAddress,temp.stateAddress,temp.createdBy,temp.CPTIDs,temp.centralGovtShare,temp.stateGovtShare,temp.claimStatus);
    }
}










