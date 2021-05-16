// File: contracts/KimochiToken.sol

pragma solidity 0.8.0;

// KimochiToken with Governance.
contract SwiftToken is ERC20("SwiftToken", "SWIFT"), Ownable {
	uint256 private _cap = 100000000e18;
	uint256 private _totalLock;

	uint256 public lockFromBlock;
	uint256 public lockToBlock;
	uint256 public transferBurnRate;
	bool public farmingEnabled;
	
	mapping(address => bool) internal minters;
	mapping(address => uint256) internal minterAllowed;
	address public masterMinter;
    uint public mintersLength_;

	mapping(address => uint256) private _locks;
	mapping(address => bool) private _transferBurnAddresses;
	mapping(address => uint256) private _lastUnlockBlock;

	event MinterConfigured(address indexed minter, uint256 minterAllowedAmount);
	event MinterRemoved(address indexed oldMinter);
	event MasterMinterChanged(address indexed newMasterMinter);
	event Lock(address indexed to, uint256 value);

	/**
	 * @dev Returns the cap on the token's total supply.
	 */
	function cap() public view returns (uint256) {
		return _cap;
	}

	function circulatingSupply() public view returns (uint256) {
		return totalSupply().sub(_totalLock);
	}

	function totalLock() public view returns (uint256) {
		return _totalLock;
	}

	/**
	 * @dev See {ERC20-_beforeTokenTransfer}.
	 *
	 * Requirements:
	 *
	 * - minted tokens must not cause the total supply to go over the cap.
	 */
	function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
		super._beforeTokenTransfer(from, to, amount);

		if (from == address(0)) { // When minting tokens
			require(totalSupply().add(amount) <= _cap, "ERC20Capped: cap exceeded");
		}
	}

	/**
	 * @dev Moves tokens `amount` from `sender` to `recipient`.
	 *
	 * This is internal function is equivalent to {transfer}, and can be used to
	 * e.g. implement automatic token fees, slashing mechanisms, etc.
	 *
	 * Emits a {Transfer} event.
	 *
	 * Requirements:
	 *
	 * - `sender` cannot be the zero address.
	 * - `recipient` cannot be the zero address.
	 * - `sender` must have a balance of at least `amount`.
	 */
	function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
		if (transferBurnRate > 0 && _transferBurnAddresses[recipient] == true && recipient != address(0)) {
			uint256 _burntAmount = amount * transferBurnRate / 100;
			// Burn transferBurnRate% from amount
			super._burn(sender, _burntAmount);
			// Recalibrate the transfer amount
			amount = amount - _burntAmount;
		}

		super._transfer(sender, recipient, amount);
	}

	/// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
	function mint(address _to, uint256 _amount) public onlyMasterMinter {
		require(_to != address(0));
		require(_amount > 0);
		uint256 mintingAllowedAmount = minterAllowed[_to];
		require(_amount <= mintingAllowedAmount);
		minterAllowed[_to] = mintingAllowedAmount.sub(_amount);
		_mint(_to, _amount);
	}

	function totalBalanceOf(address _holder) public view returns (uint256) {
		return _locks[_holder].add(balanceOf(_holder));
	}

	function lockOf(address _holder) public view returns (uint256) {
		return _locks[_holder];
	}

	function lastUnlockBlock(address _holder) public view returns (uint256) {
		return _lastUnlockBlock[_holder];
	}

	function lock(address _holder, uint256 _amount) public onlyOwner {
		require(_holder != address(0), "ERC20: lock to the zero address");
		require(_amount <= balanceOf(_holder), "ERC20: lock amount over blance");

		_transfer(_holder, address(this), _amount);

		_locks[_holder] = _locks[_holder].add(_amount);
		_totalLock = _totalLock.add(_amount);
		if (_lastUnlockBlock[_holder] < lockFromBlock) {
			_lastUnlockBlock[_holder] = lockFromBlock;
		}
		emit Lock(_holder, _amount);
	}

	function canUnlockAmount(address _holder) public view returns (uint256) {
		if (block.number < lockFromBlock) {
			return 0;
		}
		else if (block.number >= lockToBlock) {
			return _locks[_holder];
		}
		else {
			uint256 releaseBlock = block.number.sub(_lastUnlockBlock[_holder]);
			uint256 numberLockBlock = lockToBlock.sub(_lastUnlockBlock[_holder]);
			return _locks[_holder].mul(releaseBlock).div(numberLockBlock);
		}
	}

	function unlock() public {
		require(_locks[msg.sender] > 0, "ERC20: cannot unlock");
		
		uint256 amount = canUnlockAmount(msg.sender);
		// just for sure
		if (amount > balanceOf(address(this))) {
			amount = balanceOf(address(this));
		}
		_transfer(address(this), msg.sender, amount);
		_locks[msg.sender] = _locks[msg.sender].sub(amount);
		_lastUnlockBlock[msg.sender] = block.number;
		_totalLock = _totalLock.sub(amount);
	}

	// This function is for dev address migrate all balance to a multi sig address
	function transferAll(address _to) public {
		_locks[_to] = _locks[_to].add(_locks[msg.sender]);

		if (_lastUnlockBlock[_to] < lockFromBlock) {
			_lastUnlockBlock[_to] = lockFromBlock;
		}

		if (_lastUnlockBlock[_to] < _lastUnlockBlock[msg.sender]) {
			_lastUnlockBlock[_to] = _lastUnlockBlock[msg.sender];
		}

		_locks[msg.sender] = 0;
		_lastUnlockBlock[msg.sender] = 0;

		_transfer(msg.sender, _to, balanceOf(msg.sender));
	}

	/**
	 * @dev Destroys `amount` tokens from the caller.
	 *
	 * See {ERC20-_burn}.
	 */
	function burn(uint256 amount) public virtual returns (bool) {
		_burn(_msgSender(), amount);
		return true;
	}

	/**
	 * @dev Destroys `amount` tokens from `account`, deducting from the caller's
	 * allowance.
	 *
	 * See {ERC20-_burn} and {ERC20-allowance}.
	 *
	 * Requirements:
	 *
	 * - the caller must have allowance for ``accounts``'s tokens of at least
	 * `amount`.
	 */
	function burnFrom(address account, uint256 amount) public virtual returns (bool) {
		uint256 decreasedAllowance = allowance(account, _msgSender()).sub(amount, "ERC20: burn amount exceeds allowance");

		_approve(account, _msgSender(), decreasedAllowance);
		_burn(account, amount);
		return true;
	}

	function addTransferBurnAddress(address _transferBurnAddress) public onlyOwner {
		_transferBurnAddresses[_transferBurnAddress] = true;
	}

	function removeTransferBurnAddress(address _transferBurnAddress) public onlyOwner {
		delete _transferBurnAddresses[_transferBurnAddress];
	}

	modifier onlyMasterMinter() {
		require(msg.sender == masterMinter);
		_;
	}

	function configureMinter(address minter, uint256 minterAllowedAmount) onlyMasterMinter public {
	    require(mintersLength_ < 2);
	    if(!minters[minter]) {
          	minters[minter] = true;
		    minterAllowed[minter] = minterAllowedAmount;
	    	mintersLength_ += 1;
	    	emit MinterConfigured(minter, minterAllowedAmount);
        }
	}
	
	function removeMinter(address minter) onlyMasterMinter public {
	    if((minters[minter])){
    	    mintersLength_ -= 1;
    		minters[minter] = false;
    		minterAllowed[minter] = 0;
    		emit MinterRemoved(minter);
	    }
	}
	
	function updateMasterMinter(address _newMasterMinter) onlyOwner public {
		require(_newMasterMinter != address(0));
		masterMinter = _newMasterMinter;
		emit MasterMinterChanged(masterMinter);
	}
	
	
	function startFarming(uint256 numblock) public onlyOwner {
		require(farmingEnabled == false, "Farming has been started already!");
		lockFromBlock = block.number;
		lockToBlock = lockFromBlock + numblock;
		farmingEnabled = true;
	}

	constructor() public {
		lockFromBlock = 999999999;
		lockToBlock = 999999999;
		farmingEnabled = false;
		transferBurnRate = 2;
	}
}