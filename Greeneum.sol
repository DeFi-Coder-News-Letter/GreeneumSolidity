pragma solidity ^0.4.11;

contract Greeneum {


	enum Type { /* Type and area used for energy metadata */
		Solar,
		Wind,
		Hydro
	}

	enum Area {
		AfricaSubSahara,
		AfricaWest,
		MiddleEast,
		CentralAsia,
		EastAsia,
		Oceania,
		EasternEurope,
		WesternEurope,
		NorthAmericaNorthWest,
		NorthAmericaSouthWest,
		NorthAmericaCentral,
		NorthAmericaNorthEast, //Alaska
		NorthAmericaSouthEast,
		SouthAmericaWest,
		SouthAmericaEast
	}

	struct Commitment { /* blocking some money for "coloring" with specified metadata, this object saves the offer for validators to bid on */
		uint originalAmountGrey;
		uint offersRecieved;
		//Type type;
		uint amountEnergy;
		//Area area;
		uint hash;
		//Validator[] offers;
	}

	struct Validator { /* the validator id, with rating and notification for sent data */
		address holder;
		string title;
		uint8 rating;
		uint reviews;
		uint ip;
		mapping(address => bool) pendingAp;
		mapping(address => bool) canRate;
	}

	struct Consumption { /* The record of consuming clean energy, used as carbon credits */
		address consumer;
		uint amount;
		string message;
	}

    mapping (address => mapping (address => uint)) allowedGrey; /* to approve others to spend grey coins */
    mapping (address => mapping (address => uint)) allowedGreen; /* to approve others to spend green coins */
    mapping (address => uint) public consumed; /* green consumption counter */
	mapping (address => uint) private greenBalance; /* green coins balance */
	mapping (address => uint) private greyBalance; /* grey coins balance */
	mapping (address => uint) private locked; /* locked coins, that have been commited */
	mapping (uint => bool) private usedHash; /* post data hash to prevent commiting for the same data twice */
	mapping (uint => uint) private amountLeft; /* amount of coins left for the current packet being bidded on */
	mapping (address => Validator) public validatorRegistry; /* a database of all the registered validators */
	mapping (address => Validator[3]) public choises; /* a database to keep the choises a producer can make choosing his validator */


	string public constant symbol = "GRE";
    string public constant name = "Greeneum";
    uint8 public constant decimals = 18;
    

	Commitment[] public commitments; /*this is the list of commitments being filled at the moment */
	Commitment[][] public packet; /* once the list is full it is entered in the packet, where validators can bid on it */
	Consumption[] public consumptionHistory; /* a record that is kept of the consumption transactions */

	uint public totsupply; /* total number of grey coins (not maintained) */
	uint public totsupplyGreen; /* total number of green coins (not maintained) */
	uint public vpur; /* validation percentage update rate, how long between updates of the price validators pay for data */
	uint public nove; /* number of validators expected, meant to help establish the price fro data */
	uint public cpp; /* commitments per packet, how long a commitment list needs to be before it can be bidded on */
	uint public pendingPacketsIndex; /* the index on "packet" where the packet being compiled currently will be inserted */
	uint public biddingIndex; /* the index on "packet" where bidding for commitments starts */
	uint public pendingIndexAmount; /* a counter for the total amount of coins being commited in the current packet */
	uint public validationPercentage; /* the price of data as a percentage of the coins being validated */
	uint public lastPercentageUpdateTime; /* a record of when the price of data was last updated */
	uint public commitmentCounter; /* number of all commitments ever, used to calculate ratio with bid counter */
	uint public bidCounter; /* the ration of the number of bids to the number of commitments is assumed to be
	 the number of active validators for data price calculation */
	uint private seed; /* used for choosing random commitments */

	
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
 	event TransferGreen(address indexed _from, address indexed _to, uint256 _value);
    event ApprovalGreen(address indexed _owner, address indexed _spender, uint256 _value);

    
    event Commited(address indexed _commiter, uint _amount, Type _type, uint _amountEnergy, Area _area);//first grey coins are commited
    // the validators will then bid until 3 validators are matched with the commiter then
    event DecisionAvailable(address _at);// the commiter may choose which validator to send the data to
    // the commiter sends the data to the ip of the chosen validator
    event ValidatorChosen(address indexed _commiter, string _title); // the validator is notified that he needs to approve or reject
    event EnergyValidated(/*string _title, */address indexed _commiter, uint _amount); // the commiter now gets the coins he locked as green coins
    event EnergyRejected(/*string _title, */address indexed _commiter, uint _amount); // the commiter gets the coins he locked back as grey
    event ValidatorRated(address indexed _commiter, string _title, uint _rating); // the commiter can then rate his validator for speed and accuracy
    event ConsumedGreen(address consumer, uint amount, string text); // main application of the contract, equivilant to a carbon credit
    
    /* the percentage must be maintained so that there are enough competing validators on the one hand,
    	and that validators cannot freely validate random energy to reach their own commitment */
    event validationPercentageUpdated(uint oldp, uint newp); 


	modifier onlyValidator() {
		//assert(validatorRegistry[msg.sender].length != 0); // is not null
		_;
	}

	modifier notValidator() {
		//assert(validatorRegistry[msg.sender].length == 0);// is null
		_;
	}

	function Greeneum(
		uint totalSupply,// ~65,000,000
		uint totalSupplyGreen,// ~35,000,000
		uint validationPercentageUpdateRate,// constants for calculating validation percentage
		uint numberOfValidatorsExpected,
		uint initialValidationPercentage,
		uint commitmentsPerPack,
		uint randomSeed) {
		totsupply = totalSupply;
		totsupplyGreen = totalSupplyGreen;
		vpur = validationPercentageUpdateRate;
		nove = numberOfValidatorsExpected;
		cpp = commitmentsPerPack;
		pendingPacketsIndex = 0;
		biddingIndex = 0;
		validationPercentage = initialValidationPercentage;
		commitmentCounter = 0;
		bidCounter = 0;
		// TODO - get supply from crowdfund
	}

	// --------------{{ ERC20 - 1 grey }}--------------
 

    function totalSupply() constant returns (uint256 totalSupply) {
        totalSupply = totsupply;
    }

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return greyBalance[_owner];
    }

    function transfer(address _to, uint256 _amount) returns (bool success) {
        if (greyBalance[msg.sender] >= _amount 
            && _amount > 0
            && greyBalance[_to] + _amount > greyBalance[_to]) {
            greyBalance[msg.sender] -= _amount;
            greyBalance[_to] += _amount;
            Transfer(msg.sender, _to, _amount);
            return true;
        } else {
            return false;
        }
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) returns (bool success) {
        if (greyBalance[_from] >= _amount
            && allowedGrey[_from][msg.sender] >= _amount
            && _amount > 0
            && greyBalance[_to] + _amount > greyBalance[_to]) {
            greyBalance[_from] -= _amount;
            allowedGrey[_from][msg.sender] -= _amount;
            greyBalance[_to] += _amount;
            Transfer(_from, _to, _amount);
            return true;
        } else {
            return false;
        }
    }

    function approve(address _spender, uint256 _amount) returns (bool success) {
        allowedGrey[msg.sender][_spender] = _amount;
        Approval(msg.sender, _spender, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
        return allowedGrey[_owner][_spender];
    }





	// --------------{{ ERC20 - 2 green }}--------------


	function totalSupplyGreen() constant returns (uint256 totalGreenSupply) {
        totalGreenSupply = totsupply;
    }

    function balanceOfGreen(address _owner) constant returns (uint256 balance) {
        return greenBalance[_owner];
    }

    function transferGreen(address _to, uint256 _amount) returns (bool success) {
        if (greenBalance[msg.sender] >= _amount 
            && _amount > 0
            && greenBalance[_to] + _amount > greenBalance[_to]) {
            greenBalance[msg.sender] -= _amount;
            greenBalance[_to] += _amount;
            TransferGreen(msg.sender, _to, _amount);
            return true;
        } else {
            return false;
        }

    }

    function transferFromGreen(
        address _from,
        address _to,
        uint256 _amount
    ) returns (bool success) {
        if (greenBalance[_from] >= _amount
            && allowedGreen[_from][msg.sender] >= _amount
            && _amount > 0
            && greenBalance[_to] + _amount > greenBalance[_to]) {
            greenBalance[_from] -= _amount;
            allowedGreen[_from][msg.sender] -= _amount;
            greenBalance[_to] += _amount;
            TransferGreen(_from, _to, _amount);
            return true;
        } else {
            return false;
        }
    }

    function approveGreen(address _spender, uint256 _amount) returns (bool success) {
        allowedGreen[msg.sender][_spender] = _amount;
        ApprovalGreen(msg.sender, _spender, _amount);
        return true;
    }

    function allowanceGreen(address _owner, address _spender) constant returns (uint256 remaining) {
        return allowedGreen[_owner][_spender];
    }



    // --------------{{ GREENEUM special features }}--------------


	/* commit coins to be colored green (if approved by the validator) */
    function commit(uint _amountGrey, Type _type, uint _amountEnergy, Area _area, uint _hash) public returns (uint) { 
    	if(greyBalance[msg.sender] < _amountGrey) throw;
    	if(usedHash[_hash]) throw;
    	if(choises[msg.sender].length == 0) throw; //is null, need to make decisions before making more commitments
    	usedHash[_hash] = true;
    	greyBalance[msg.sender] -= _amountGrey;
    	locked[msg.sender] += _amountGrey;
    	//Validator[3] valarr = new Validator[];
    	commitments.push(
    		Commitment({
    				sender: msg.sender,
    				amountGrey: _amountGrey,
    				originalAmountGrey: _amountGrey,
    				//type: _type,
    				amountEnergy: _amountEnergy,
    				//area: _area,
    				hash: _hash,
    				offersRecieved: 0,
    				//offers: valarr
    			}));
    	pendingIndexAmount += _amountGrey;
    	Commited(msg.sender, _amountGrey, _type, _amountEnergy, _area);
    	commitmentCounter++;
    	seed = seed^_hash;
    	if(commitments.length == cpp) releasePacket();
    	return pendingPacketsIndex;
    }

    /* once the cpp is reached the commitments are released to be bid on */
    function releasePacket() private {
    	packet.push(commitments);
    	pendingPacketsIndex++;
    	amountLeft[pendingPacketsIndex] = 3*pendingIndexAmount;
    	pendingIndexAmount = 0;
    }

    /* a validator can bid on data from random commitments */
    function bid(uint _amountGrey, Type _type, uint _amountEnergy, Area _area, uint ip) public onlyValidator { // offers must be sent to random commitments!
    	uint left = _amountGrey;
    	uint packetIndex = biddingIndex; // start with last open packet
    	uint commitmentIndex = 0;
    	uint rate = _amountEnergy/_amountGrey;
    	Commitment memory comHolder;
    	updateValidationPercentage();
    	assert(greenBalance[msg.sender] > _amountGrey*validationPercentage/1000); //validation percentage is 0.1%
    	while(left != 0 && packetIndex < pendingPacketsIndex){ //finished making offers or finished available commitments
    		uint random = seed%cpp;
    		for(commitmentIndex = 0; commitmentIndex < pendingPacketsIndex; commitmentIndex += random){
    			comHolder = packet[packetIndex][commitmentIndex];
    			if(//comHolder.type == _type &&
    				//comHolder.area == _area &&
    				rate > comHolder.amountEnergy/comHolder.amountGrey &&
    				comHolder.offersRecieved < 3){ // an offer will be made
    				//Validator me;
    				if(left > comHolder.amountGrey){
    					left -= comHolder.amountGrey;
    					amountLeft[packetIndex] -= comHolder.amountGrey;
    					greyBalance[msg.sender] -= comHolder.amountGrey*validationPercentage/1000;
    					greyBalance[comHolder.sender] += comHolder.amountGrey*validationPercentage/1000;
    					comHolder.amountGrey = comHolder.originalAmountGrey;
    					comHolder.offersRecieved++;
    					//me = validatorRegistry[msg.sender];
    					//me.ip = ip;
    					//comHolder.offers.push(me);
    					if(comHolder.offersRecieved == 3) sendForDecision(/*comHolder.offers,*/ comHolder.sender);

    				}
    				else{
    					comHolder.amountGrey -= left;
    					amountLeft[packetIndex] -= left;
    					greyBalance[msg.sender] -= left*validationPercentage/1000;
    					greyBalance[comHolder.sender] += left*validationPercentage/1000;
    					//me = validatorRegistry[msg.sender];
    					//me.ip = ip;
    					//comHolder.offers.push(me);
    					if(comHolder.offersRecieved == 3) sendForDecision(/*comHolder.offers, */comHolder.sender);
    					left = 0;
    				}
    				bidCounter++;
    				if(amountLeft[packetIndex] == 0) biddingIndex++;
    			}
    		}
    		packetIndex++;
    	}
    }

	/* 3 validators have been compiled for this commitment, time for the producer to choose */
    function sendForDecision(/*Validator[] offrs, */address chooser) private {
    	if(choises[chooser].length == 0) throw; //is null, need to make decisions before making more commitments
    	//choises[chooser] = offrs;
    	DecisionAvailable(chooser);
    }
	/* if the time has come, a new price for data */
    function updateValidationPercentage() private {
    	if(now > lastPercentageUpdateTime + vpur){
    		lastPercentageUpdateTime = now;
    		uint bidsPerCommitment = bidCounter/commitmentCounter;
    		bidCounter = 0;
    		commitmentCounter = 0;
    		int factor = int(bidsPerCommitment - nove);
    		uint oldvalidationPercentage = validationPercentage;
    		//validationPercentage = validationPercentage * (2**factor); - TODO - fix
    		validationPercentageUpdated(oldvalidationPercentage, validationPercentage);
    	}
    }
	/* a producer can use this to see his validator options */
    function getDecision() public constant returns (
    	address holder1, string title1, uint8 rating1,	uint reviews1, uint ip1,
    	address holder2, string title2, uint8 rating2,	uint reviews2, uint ip2,
    	address holder3, string title3, uint8 rating3,	uint reviews3, uint ip3
    	){
    	if(choises[msg.sender].length == 0){//is null
    		holder1 = choises[msg.sender][0].holder;
    		holder2 = choises[msg.sender][1].holder;
    		holder3 = choises[msg.sender][2].holder;
    		title1 = choises[msg.sender][0].title;
    		title2 = choises[msg.sender][1].title;
    		title3 = choises[msg.sender][2].title;
    		rating1 = choises[msg.sender][0].rating;
    		rating2 = choises[msg.sender][1].rating;
    		rating3 = choises[msg.sender][2].rating;
    		reviews1 = choises[msg.sender][0].reviews;
    		reviews2 = choises[msg.sender][1].reviews;
    		reviews3 = choises[msg.sender][2].reviews;
    		ip1 = choises[msg.sender][0].ip;
    		ip2 = choises[msg.sender][1].ip;
    		ip3 = choises[msg.sender][2].ip;
    	}
    }
	/* the producer has chosen a validator, sent the data and enters his decision */
    function makeDecision(uint8 chois) public {
    	if(chois > 3) throw;
    	if(choises[msg.sender].length == 0){ //is null
    		validatorRegistry[choises[msg.sender][chois - 1].holder].pendingAp[msg.sender] = true;
    		//choises[msg.sender] = 0;
    	}
    	ValidatorChosen(msg.sender, validatorRegistry[choises[msg.sender][chois - 1].holder].title);
    } // TODO - find way to prompt validator to respond

	/* once the data is recieved the validator must either approve the data */
    function approveValidation(address dataSender) public {
    	if(validatorRegistry[msg.sender].pendingAp[dataSender]){
    		validatorRegistry[msg.sender].pendingAp[dataSender] = false;
    		validatorRegistry[msg.sender].canRate[dataSender] = true;
    		uint temp = locked[dataSender];
    		locked[dataSender] = 0;
    		greenBalance[dataSender] += temp;
    		EnergyValidated(/*validatorRegistry[msg.sender], */dataSender, temp);
    	}
    }

	/* or reject the data */
    function rejectValidation(address dataSender) public {
    	if(validatorRegistry[msg.sender].pendingAp[dataSender]){
    		validatorRegistry[msg.sender].pendingAp[dataSender] = false;
    		validatorRegistry[msg.sender].canRate[dataSender] = true;
    		uint temp = locked[dataSender];
    		locked[dataSender] = 0;
    		greyBalance[dataSender] += temp;
    		EnergyRejected(/*validatorRegistry[msg.sender], */dataSender, temp);
    	}
    }

	/* once the data is rejected or approved the producer can rank the validator */
    function rateValidator(address validatorAddr, uint8 rating) public {
    	assert(validatorRegistry[validatorAddr].canRate[msg.sender]);
    	validatorRegistry[validatorAddr].canRate[msg.sender] = false;
    	uint totalRating = validatorRegistry[validatorAddr].reviews * validatorRegistry[validatorAddr].rating;
    	validatorRegistry[validatorAddr].reviews++;
    	validatorRegistry[validatorAddr].rating = uint8((totalRating + rating)/validatorRegistry[validatorAddr].reviews);
    	ValidatorRated(msg.sender, validatorRegistry[validatorAddr].title, rating);
    }

	/* make a consumption transaction, keep the record of having consumed green energy */
    function consume(uint _amount, string text) public {
    	assert(greenBalance[msg.sender] > _amount);
    	greenBalance[msg.sender] -= _amount;
    	consumptionHistory.push(Consumption({
    		consumer: msg.sender,
    		amount: _amount,
    		message: text
    		}));
    	consumed[msg.sender] += _amount;
    	ConsumedGreen(msg.sender, _amount, text);
    }

	/* for any budding validators looking to get into energy data machine learning */
    function registerAsValidator(string _title, uint _ip) public notValidator {
    	validatorRegistry[msg.sender] = Validator({
			holder: msg.sender,
			title: _title,
			rating: 0,
			reviews: 0,
			ip: _ip,
		});
    }
	/* for validator mobility */
    function changeValidatorTitle(string _title) public onlyValidator {
    	validatorRegistry[msg.sender].title = _title;
    }
	/* for validator mobility */
    function changeValidatorIp(uint _ip) public onlyValidator {
    	validatorRegistry[msg.sender].ip = _ip;
    }

	function() {
      throw;
    }
}