module ipx::ipx {
  use std::option;

  use sui::object::{Self, UID};
  use sui::tx_context::{Self, TxContext};
  use sui::balance::{Self, Supply, Balance};
  use sui::bag::{Self, Bag};
  use sui::table::{Self, Table};
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::url;
  use sui::event;

  use ipx::utils::{get_coin_info};

  struct IPX has drop {}

  const START_EPOCH: u64 = 4; // TODO needs to be updated based on real time before mainnet
  const IPX_PER_EPOCH: u64 = 100000000000; // 100e9 IPX | 100 IPX per epoch
  const IPX_PRE_MINT_AMOUNT: u64 = 600000000000000000; // 600M 60% of the supply
  const DEV: address = @dev;

  const ERROR_POOL_ADDED_ALREADY: u64 = 1;
  const ERROR_ACCOUNT_BAG_ADDED_ALREADY: u64 = 2;
  const ERROR_NOT_ENOUGH_BALANCE: u64 = 3;
  const ERROR_NO_PENDING_REWARDS: u64 = 4;

  struct IPXStorage has key {
    id: UID,
    supply: Supply<IPX>,
    ipx_per_epoch: u64,
    total_allocation_points: u64,
    pool_keys: Table<vector<u8>, PoolKey>,
    pools: Table<u64, Pool>,
    start_epoch: u64
  }

  struct Pool has key, store {
    id: UID,
    allocation_points: u64,
    last_reward_epoch: u64,
    accrued_ipx_per_share: u256,
    balance_value: u64
  }

  struct AccountStorage has key {
    id: UID,
    accounts: Table<u64, Bag>
  }

  struct Account<phantom T> has key, store {
    id: UID,
    balance: Balance<T>,
    rewards_paid: u256
  }

  struct PoolKey has key, store {
    id: UID,
    key: u64
  }

  struct IPXAdmin has key {
    id: UID
  }

  // Events

  struct SetAllocationPoints<phantom T> has drop, copy {
    key: u64,
    allocation_points: u64,
  }

  struct AddPool<phantom T> has drop, copy {
    key: u64,
    allocation_points: u64,
  }

  struct Stake<phantom T> has drop, copy {
    sender: address,
    amount: u64,
    pool_key: u64,
    rewards: u64
  }

  struct Unstake<phantom T> has drop, copy {
    sender: address,
    amount: u64,
    pool_key: u64,
    rewards: u64
  }


  struct NewAdmin has drop, copy {
    admin: address
  }

  fun init(witness: IPX, ctx: &mut TxContext) {
      // Create the IPX governance token with 9 decimals
      let (treasury, metadata) = coin::create_currency<IPX>(
            witness, 
            9,
            b"IPX",
            b"Interest Protocol Token",
            b"The governance token of Interest Protocol",
            option::some(url::new_unsafe_from_bytes(b"https://www.interestprotocol.com")),
            ctx
        );

      // Set up tables for the storage objects 
      let pools = table::new<u64, Pool>(ctx);  
      let pool_keys = table::new<vector<u8>, PoolKey>(ctx);
      let accounts = table::new<u64, Bag>(ctx);
      
      // Register the IPX farm in pool_keys
      table::add(
        &mut pool_keys, 
        get_coin_info<IPX>(), 
        PoolKey { 
          id: object::new(ctx), 
          key: 0,
          }
        );

      // Register the IPX farm on pools
      table::add(
        &mut pools, 
        0, // Key is the length of the bag before a new element is added 
        Pool {
          id: object::new(ctx),
          allocation_points: 1000,
          last_reward_epoch: START_EPOCH,
          accrued_ipx_per_share: 0,
          balance_value: 0
        }
      );

      // Transform the treasury_cap into a supply struct to allow this contract to mint/burn IPX
      let supply = coin::treasury_into_supply(treasury);

      // Pre-mint 60% of the supply to distribute
      transfer::transfer(
        coin::from_balance(
          balance::increase_supply(&mut supply, IPX_PRE_MINT_AMOUNT), ctx
        ),
        DEV
      );

      // Freeze the metadata object
      transfer::freeze_object(metadata);

      // Share IPXStorage
      transfer::share_object(
        IPXStorage {
          id: object::new(ctx),
          supply,
          pools,
          ipx_per_epoch: IPX_PER_EPOCH,
          total_allocation_points: 1000,
          pool_keys,
          start_epoch: START_EPOCH
        }
      );

      // Share the Account Storage
      transfer::share_object(
        AccountStorage {
          id: object::new(ctx),
          accounts
        }
      );

      // Give the admin_cap to the deployer
      transfer::transfer(IPXAdmin { id: object::new(ctx) }, tx_context::sender(ctx));
  }

/**
* @notice It returns the number of Coin<IPX> rewards an account is entitled to for T Pool
* @param storage The IPXStorage shared object
* @param accounts_storage The AccountStorage shared objetct
* @param account The function will return the rewards for this address
* @return rewards
*/
 public fun get_pending_rewards<T>(
  storage: &IPXStorage,
  account_storage: &AccountStorage,
  account: address,
  ctx: &mut TxContext
  ): u256 {
    
    // If the user never deposited in T Pool, return 0
    if ((!bag::contains<address>(table::borrow(&account_storage.accounts, get_pool_key<T>(storage)), account))) return 0;

    // Borrow the pool
    let pool = borrow_pool<T>(storage);
    // Borrow the user account for T pool
    let account = borrow_account<T>(storage, account_storage, account);

    // Get the value of the total number of coins deposited in the pool
    let total_balance = (pool.balance_value as u256);
    // Get the value of the number of coins deposited by the account
    let account_balance_value = (balance::value(&account.balance) as u256);

    // If the pool is empty or the user has no tokens in this pool return 0
    if (account_balance_value == 0 || total_balance == 0) return 0;

    // Save the current epoch in memory
    let current_epoch = tx_context::epoch(ctx);
    // save the accrued ipx per share in memory
    let accrued_ipx_per_share = pool.accrued_ipx_per_share;

    // If the pool is not up to date, we need to increase the accrued_ipx_per_share
    if (current_epoch > pool.last_reward_epoch) {
      // Calculate how many epochs have passed since the last update
      let epochs_delta = ((current_epoch - pool.last_reward_epoch) as u256);
      // Calculate the total rewards for this pool
      let rewards = (epochs_delta * (storage.ipx_per_epoch as u256)) * (pool.allocation_points as u256) / (storage.total_allocation_points as u256);
      // Update the accrued_ipx_per_share
      accrued_ipx_per_share = accrued_ipx_per_share + (rewards / (pool.balance_value as u256));
    };

    // Calculate the rewards for the user
    return (account_balance_value * accrued_ipx_per_share) - account.rewards_paid
  }

/**
* @notice It allows the caller to deposit Coin<T> in T Pool. It returns any pending rewards Coin<IPX>
* @param storage The IPXStorage shared object
* @param accounts_storage The AccountStorage shared objetct
* @param token The Coin<T>, the caller wishes to deposit
* @return Coin<IPX> pending rewards
*/
 public fun stake<T>(
  storage: &mut IPXStorage, 
  accounts_storage: &mut AccountStorage,
  token: Coin<T>,
  ctx: &mut TxContext
 ): Coin<IPX> {
  // We need to update the pool rewards before any mutation
  update_pool<T>(storage, ctx);
  // Save the sender in memory
  let sender = tx_context::sender(ctx);

   // Register the sender if it is his first time depositing in this pool 
  if (!bag::contains<address>(table::borrow(&accounts_storage.accounts, get_pool_key<T>(storage)), sender)) {
    bag::add(
      table::borrow_mut(&mut accounts_storage.accounts, get_pool_key<T>(storage)),
      sender,
      Account<T> {
        id: object::new(ctx),
        balance: balance::zero<T>(),
        rewards_paid: 0
      }
    );
  };

  // Get the needed info to fetch the sender account and the pool
  let key = get_pool_key<T>(storage);
  let pool = borrow_mut_pool<T>(storage);
  let account = borrow_mut_account<T>(accounts_storage, key, sender);

  // Initiate the pending rewards to 0
  let pending_rewards = 0;
  
  // Save in memory the current number of coins the sender has deposited
  let account_balance_value = (balance::value(&account.balance) as u256);

  // If he has deposited tokens, he has earned Coin<IPX>; therefore, we update the pending rewards based on the current balance
  if (account_balance_value > 0) pending_rewards = (account_balance_value * pool.accrued_ipx_per_share) - account.rewards_paid;

  // Save in memory how mnay coins the sender wishes to deposit
  let token_value = coin::value(&token);

  // Update the pool balance
  pool.balance_value = pool.balance_value + token_value;
  // Update the Balance<T> on the sender account
  balance::join(&mut account.balance, coin::into_balance(token));
  // Consider all his rewards paid
  account.rewards_paid = (balance::value(&account.balance) as u256) * pool.accrued_ipx_per_share;

  event::emit(
    Stake<T> {
      pool_key: key,
      amount: token_value,
      sender,
      rewards: (pending_rewards as u64)
    }
  );

  // Mint Coin<IPX> rewards for the caller.
  coin::from_balance(balance::increase_supply(&mut storage.supply, (pending_rewards as u64)), ctx)
 }

/**
* @notice It allows the caller to withdraw Coin<T> from T Pool. It returns any pending rewards Coin<IPX>
* @param storage The IPXStorage shared object
* @param accounts_storage The AccountStorage shared objetct
* @param coin_value The value of the Coin<T>, the caller wishes to withdraw
* @return (Coin<IPX> pending rewards, Coin<T>)
*/
 public fun unstake<T>(
  storage: &mut IPXStorage, 
  accounts_storage: &mut AccountStorage,
  coin_value: u64,
  ctx: &mut TxContext
 ): (Coin<IPX>, Coin<T>) {
  // Need to update the rewards of the pool before any  mutation
  update_pool<T>(storage, ctx);
  
  // Get mutable struct of the Pool and Account
  let key = get_pool_key<T>(storage);
  let pool = borrow_mut_pool<T>(storage);
  let account = borrow_mut_account<T>(accounts_storage, key, tx_context::sender(ctx));
  
  // Save the account balance value in memory
  let account_balance_value = balance::value(&account.balance);

  // The user must have enough balance value
  assert!(account_balance_value >= coin_value, ERROR_NOT_ENOUGH_BALANCE);

  // Calculate how many rewards the caller is entitled to
  let pending_rewards = ((account_balance_value as u256) * pool.accrued_ipx_per_share) - account.rewards_paid;

  // Withdraw the Coin<T> from the Account
  let staked_coin = coin::take(&mut account.balance, coin_value, ctx);

  // Reduce the balance value in the pool
  pool.balance_value = pool.balance_value - coin_value;
  // Consider all pending rewards paid
  account.rewards_paid = (balance::value(&account.balance) as u256) * pool.accrued_ipx_per_share;

  event::emit(
    Unstake<T> {
      pool_key: key,
      amount: coin_value,
      sender: tx_context::sender(ctx),
      rewards: (pending_rewards as u64)
    }
  );

  // Mint Coin<IPX> rewards and returns the Coin<T>
  (
    coin::from_balance(balance::increase_supply(&mut storage.supply, (pending_rewards as u64)), ctx),
    staked_coin
  )
 } 

 /**
 * @notice It allows a caller to get all his pending rewards from T Pool
 * @param storage The IPXStorage shared object
 * @param accounts_storage The AccountStorage shared objetct
 * @return Coin<IPX> the pending rewards
 */
 public fun get_rewards<T>(
  storage: &mut IPXStorage, 
  accounts_storage: &mut AccountStorage,
  ctx: &mut TxContext
 ): Coin<IPX> {
  // Update the pool before any mutation
  update_pool<T>(storage, ctx);
  
  // Get mutable Pool and Account structs
  let key = get_pool_key<T>(storage);
  let pool = borrow_pool<T>(storage);
  let account = borrow_mut_account<T>(accounts_storage, key, tx_context::sender(ctx));
  
  // Save the user balance value in memory
  let account_balance_value = (balance::value(&account.balance) as u256);

  // Calculate his pending rewards
  let pending_rewards = (account_balance_value * pool.accrued_ipx_per_share) - account.rewards_paid;

  // No point to keep going if there are no rewards
  assert!(pending_rewards != 0, ERROR_NO_PENDING_REWARDS);
  
  // Consider all rewards paid
  account.rewards_paid = account_balance_value * pool.accrued_ipx_per_share;

  // Mint Coin<IPX> rewards to the caller
  coin::from_balance(balance::increase_supply(&mut storage.supply, (pending_rewards as u64)), ctx)
 }

 /**
 * @notice Updates the reward info of all pools registered in this contract
 * @param storage The IPXStorage shared object
 */
 public fun update_all_pools(storage: &mut IPXStorage, ctx: &mut TxContext) {
  // Find out how many pools are in the contract
  let length = table::length(&storage.pools);

  // Index to keep track of how many pools we have updated
  let index = 0;

  // Loop to iterate through all pools
  while (index < length) {
    // Save in memory key information before mutating the storage struct
    let ipx_per_epoch = storage.ipx_per_epoch;
    let total_allocation_points = storage.total_allocation_points;
    let start_epoch = storage.start_epoch;

    // Borrow mutable Pool Struct
    let pool = table::borrow_mut(&mut storage.pools, index);

    // Update the pool
    update_pool_internal(pool, ipx_per_epoch, total_allocation_points, start_epoch, ctx);

    // Increment the index
    index = index + 1;
  }
 }  

 /**
 * @notice Updates the reward info for T Pool
 * @param storage The IPXStorage shared object
 */
 public fun update_pool<T>(storage: &mut IPXStorage, ctx: &mut TxContext) {
  // Save in memory key information before mutating the storage struct
  let ipx_per_epoch = storage.ipx_per_epoch;
  let total_allocation_points = storage.total_allocation_points;
  let start_epoch = storage.start_epoch;

  // Borrow mutable Pool Struct
  let pool = borrow_mut_pool<T>(storage);

  // Update the pool
  update_pool_internal(pool, ipx_per_epoch, total_allocation_points, start_epoch, ctx);
 }

 /**
 * @notice It allows the sender to burn Coin<IPX>. Core team will use to reduce IPX supply with protocol profits
 * @param storage The IPXStorage shared object
 * return u64 the value of Coin|<IPX> burned
 */
 public fun burn_ipx(storage: &mut IPXStorage, coin: Coin<IPX>): u64 {
    balance::decrease_supply(&mut storage.supply, coin::into_balance(coin))
 }

 /**
 * @dev The implementation of update_pool
 * @param pool T Pool Struct
 * @param ipx_per_epoch Value of Coin<IPX> this module mints per epoch
 * @param total_allocation_points The sum of all pool points
 * @param start_epoch The epoch that this module is allowed to start minting Coin<IPX>
 */
 fun update_pool_internal(
  pool: &mut Pool, 
  ipx_per_epoch: u64, 
  total_allocation_points: u64,
  start_epoch: u64,
  ctx: &mut TxContext
  ) {
  // Save the current epoch in memory  
  let current_epoch = tx_context::epoch(ctx);

  // If the pool reward info is up to date or it is not allowed to start minting return;
  if (current_epoch == pool.last_reward_epoch || start_epoch > current_epoch) return;

  // Save how many epochs have passed since the last update
  let epochs_delta = current_epoch - pool.last_reward_epoch;

  // Update the current pool last reward epoch
  pool.last_reward_epoch = current_epoch;

  // There is nothing to do if the pool is not allowed to mint Coin<IPX> or if there are no coins deposited on it.
  if (pool.allocation_points == 0 || pool.balance_value == 0) return;

  // Calculate the rewards (pool_allocation * number_of_epochs * ipx_per_epoch) / total_allocation_points
  let rewards = ((pool.allocation_points as u256) * (epochs_delta as u256) * (ipx_per_epoch as u256) / (total_allocation_points as u256));

  // Update the accrued_ipx_per_share
  pool.accrued_ipx_per_share = pool.accrued_ipx_per_share + (rewards / (pool.balance_value as u256));
 }

 /**
 * @dev The updates the allocation points of the IPX Pool and the total allocation points
 * The IPX Pool must have 1/3 of all other pools allocations
 * @param storage The IPXStorage shared object
 */
 fun update_ipx_pool(storage: &mut IPXStorage) {
    // Save the total allocation points in memory
    let total_allocation_points = storage.total_allocation_points;

    // Borrow the IPX mutable pool struct
    let pool = borrow_mut_pool<IPX>(storage);

    // Get points of all other pools
    let all_other_pools_points = total_allocation_points - pool.allocation_points;

    // Divide by 3 to get the new ipx pool allocation
    let new_ipx_pool_allocation_points = all_other_pools_points / 3;

    // Calculate the total allocation points
    let total_allocation_points = total_allocation_points + new_ipx_pool_allocation_points - pool.allocation_points;

    // Update pool and storage
    pool.allocation_points = new_ipx_pool_allocation_points;
    storage.total_allocation_points = total_allocation_points;
 } 

  /**
  * @dev Finds T Pool from IPXStorage
  * @param storage The IPXStorage shared object
  * @return mutable T Pool
  */
 fun borrow_mut_pool<T>(storage: &mut IPXStorage): &mut Pool {
  let key = get_pool_key<T>(storage);
  table::borrow_mut(&mut storage.pools, key)
 }

/**
* @dev Finds T Pool from IPXStorage
* @param storage The IPXStorage shared object
* @return immutable T Pool
*/
fun borrow_pool<T>(storage: &IPXStorage): &Pool {
  let key = get_pool_key<T>(storage);
  table::borrow(&storage.pools, key)
 }

/**
* @dev Finds the key of a pool
* @param storage The IPXStorage shared object
* @return the key of T Pool
*/
 fun get_pool_key<T>(storage: &IPXStorage): u64 {
    table::borrow<vector<u8>, PoolKey>(&storage.pool_keys, get_coin_info<T>()).key
 }

/**
* @dev Finds an Account struct for T Pool
* @param storage The IPXStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param sender The address of the account we wish to find
* @return immutable AccountStruct of sender for T Pool
*/ 
 fun borrow_account<T>(storage: &IPXStorage, accounts_storage: &AccountStorage, sender: address): &Account<T> {
  bag::borrow(table::borrow(&accounts_storage.accounts, get_pool_key<T>(storage)), sender)
 }

/**
* @dev Finds an Account struct for T Pool
* @param storage The IPXStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param sender The address of the account we wish to find
* @return mutable AccountStruct of sender for T Pool
*/ 
fun borrow_mut_account<T>(accounts_storage: &mut AccountStorage, key: u64, sender: address): &mut Account<T> {
  bag::borrow_mut(table::borrow_mut(&mut accounts_storage.accounts, key), sender)
 }

/**
* @dev Updates the value of Coin<IPX> this module is allowed to mint per epoch
* @param _ the admin cap
* @param storage The IPXStorage shared object
* @param ipx_per_epoch the new ipx_per_epoch
* Requirements: 
* - The caller must be the admin
*/ 
 entry public fun update_ipx_per_epoch(
  _: &IPXAdmin,
  storage: &mut IPXStorage,
  ipx_per_epoch: u64,
  ctx: &mut TxContext
  ) {
    // Update all pools rewards info before updating the ipx_per_epoch
    update_all_pools(storage, ctx);
    storage.ipx_per_epoch = ipx_per_epoch;
 }

/**
* @dev Register a Pool for Coin<T> in this module
* @param _ the admin cap
* @param storage The IPXStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param allocaion_points The allocation points of the new T Pool
* @param update if true we will update all pools rewards before any update
* Requirements: 
* - The caller must be the admin
* - Only one Pool per Coin<T>
*/ 
 entry public fun add_pool<T>(
  _: &IPXAdmin,
  storage: &mut IPXStorage,
  accounts_storage: &mut AccountStorage,
  allocation_points: u64,
  update: bool,
  ctx: &mut TxContext
 ) {
  // Save total allocation points and start epoch in memory
  let total_allocation_points = storage.total_allocation_points;
  let start_epoch = storage.start_epoch;
  // Update all pools if true
  if (update) update_all_pools(storage, ctx);

  // Make sure Coin<T> has never been registered
  assert!(!table::contains(&storage.pool_keys, get_coin_info<T>()), ERROR_POOL_ADDED_ALREADY);

  // Update the total allocation points
  storage.total_allocation_points = total_allocation_points + allocation_points;

  // Current number of pools is the key of the new pool
  let key = table::length(&storage.pool_keys);

  // Insaniy check if the pool is not registered, there is also no Account Bag registered
  assert!(!table::contains(&accounts_storage.accounts, key), ERROR_ACCOUNT_BAG_ADDED_ALREADY);

  // Register the Account Bag
  table::add(
    &mut accounts_storage.accounts,
    key,
    bag::new(ctx)
  );

  // Register the PoolKey
  table::add(
    &mut storage.pool_keys,
    get_coin_info<T>(),
    PoolKey {
      id: object::new(ctx),
      key
    }
  );

  // Save the current_epoch in memory
  let current_epoch = tx_context::epoch(ctx);

  // Register the Pool in IPXStorage
  table::add(
    &mut storage.pools,
    key,
    Pool {
      id: object::new(ctx),
      allocation_points,
      last_reward_epoch: if (current_epoch > start_epoch) { current_epoch } else { start_epoch },
      accrued_ipx_per_share: 0,
      balance_value: 0
    }
  );

  // Emit
  event::emit(
    AddPool<T> {
      key,
      allocation_points
    }
  );

  // Update the IPX Pool allocation
  update_ipx_pool(storage);
 }

/**
* @dev Updates the allocation points for T Pool
* @param _ the admin cap
* @param storage The IPXStorage shared object
* @param allocation_points The new allocation points for T Pool
* @param update if true we will update all pools rewards before any update
* Requirements: 
* - The caller must be the admin
* - The Pool must exist
*/ 
 entry public fun set_allocation_points<T>(
  _: &IPXAdmin,
  storage: &mut IPXStorage,
  allocation_points: u64,
  update: bool,
  ctx: &mut TxContext
 ) {
  // Save the total allocation points in memory
  let total_allocation_points = storage.total_allocation_points;
  // Update all pools
  if (update) update_all_pools(storage, ctx);

  // Get Pool key and Pool mutable Struct
  let key = get_pool_key<T>(storage);
  let pool = borrow_mut_pool<T>(storage);

  // No point to update if the new allocation_points is not different
  if (pool.allocation_points == allocation_points) return;

  // Update the total allocation points
  let total_allocation_points = total_allocation_points + allocation_points - pool.allocation_points;

  // Update the T Pool allocation points
  pool.allocation_points = allocation_points;
  // Update the total allocation points
  storage.total_allocation_points = total_allocation_points;

  event::emit(
    SetAllocationPoints<T> {
      key,
      allocation_points
    }
  );

  // Update the IPX Pool allocation points
  update_ipx_pool(storage);
 }
 
 /**
 * @notice It allows the admin to transfer the AdminCap to a new address
 * @param admin The IPXAdmin Struct
 * @param recipient The address of the new admin
 */
 entry public fun transfer_admin(
  admin: IPXAdmin,
  recipient: address
 ) {
  transfer::transfer(admin, recipient);
  event::emit(NewAdmin { admin: recipient })
 }

 /**
 * @notice A getter function
 * @param storage The IPXStorage shared object
 * @param accounts_storage The AccountStorage shared object
 * @param sender The address we wish to check
 * @return balance of the account on T Pool and rewards paid 
 */
 public fun get_account_info<T>(storage: &IPXStorage, accounts_storage: &AccountStorage, sender: address): (u64, u256) {
    let account = bag::borrow<address, Account<T>>(table::borrow(&accounts_storage.accounts, get_pool_key<T>(storage)), sender);
    (
      balance::value(&account.balance),
      account.rewards_paid
    )
  }

/**
 * @notice A getter function
 * @param storage The IPXStorage shared object
 * @return allocation_points, last_reward_epoch, accrued_ipx_per_share, balance_value of T Pool
 */
  public fun get_pool_info<T>(storage: &IPXStorage): (u64, u64, u256, u64) {
    let key = get_pool_key<T>(storage);
    let pool = table::borrow(&storage.pools, key);
    (
      pool.allocation_points,
      pool.last_reward_epoch,
      pool.accrued_ipx_per_share,
      pool.balance_value
    )
  }

  /**
 * @notice A getter function
 * @param storage The IPXStorage shared object
 * @return total supply of IPX, ipx_per_epoch, total_allocation_points, start_epoch
 */
  public fun get_ipx_storage_info(storage: &IPXStorage): (u64, u64, u64, u64) {
    (
      balance::supply_value(&storage.supply),
      storage.ipx_per_epoch,
      storage.total_allocation_points,
      storage.start_epoch
    )
  }
  
  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(IPX {}, ctx);
  }

  #[test_only]
  public fun get_ipx_pre_mint_amount(): u64 {
    IPX_PRE_MINT_AMOUNT
  }
}
