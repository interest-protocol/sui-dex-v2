module ipx::interface {

  use sui::coin::{Coin};
  use sui::tx_context::{Self, TxContext};
  use sui::transfer;

  use ipx::dex_volatile::{Self as volatile, Storage as VStorage, VLPCoin};
  use ipx::dex_stable::{Self as stable, Storage as SStorage, SLPCoin};
  use ipx::ipx::{Self, IPXStorage, AccountStorage, IPX};
  use ipx::utils::{destroy_zero_or_transfer, handle_coin_vector, are_coins_sorted};
  use ipx::router;

  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It create a volatile Pool with Coins X and Y
  * @param storage The storage object of the ipx::dex_volatile 
  * @param vector_x A vector of several Coin<X> 
  * @param vector_y A vector of several Coin<Y> 
  * @param coin_x_amount The value the caller wishes to deposit for Coin<X> 
  * @param coin_y_amount The value the caller wishes to deposit for Coin<Y>
  */
  entry public fun create_pool<X, Y>(
      storage: &mut VStorage,
      vector_x: vector<Coin<X>>,
      vector_y: vector<Coin<Y>>,
      coin_x_amount: u64,
      coin_y_amount: u64,
      ctx: &mut TxContext
  ) {
    
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

    // Sorts for the caller - to make it easier for the frontend
    if (are_coins_sorted<X, Y>()) {
      transfer::transfer(
        volatile::create_pool(
          storage,
          coin_x,
          coin_y,
          ctx
        ),
        tx_context::sender(ctx)
      )
    } else {
      transfer::transfer(
        volatile::create_pool(
          storage,
          coin_y,
          coin_x,
          ctx
        ),
        tx_context::sender(ctx)
      )
    }
  }

  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It performs a swap and finds the most profitable pool. X -> Y or Y -> X on Pool<X, Y>
  * @param v_storage The storage object of the ipx::dex_volatile 
  * @param s_storage The storage object of the ipx::dex_stable 
  * @param vector_x A vector of several Coin<X> 
  * @param vector_y A vector of several Coin<Y> 
  * @param coin_x_amount The value the caller wishes to deposit for Coin<X> 
  * @param coin_y_amount The value the caller wishes to deposit for Coin<Y>
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  */
  entry public fun swap<X, Y>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    vector_x: vector<Coin<X>>,
    vector_y: vector<Coin<Y>>,
    coin_x_amount: u64,
    coin_y_amount: u64,
    coin_out_min_value: u64,
    ctx: &mut TxContext
  ) {
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

  if (are_coins_sorted<X, Y>()) {
   let (coin_x, coin_y) = router::swap<X, Y>(
      v_storage,
      s_storage,
      coin_x,
      coin_y,
      coin_out_min_value,
      ctx
    );

    destroy_zero_or_transfer(coin_x, ctx);
    destroy_zero_or_transfer(coin_y, ctx);
    } else {
    let (coin_y, coin_x) = router::swap<Y, X>(
      v_storage,
      s_storage,
      coin_y,
      coin_x,
      coin_out_min_value,
      ctx
    );
    
    destroy_zero_or_transfer(coin_x, ctx);
    destroy_zero_or_transfer(coin_y, ctx);
    }
  }

  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It performs an one hop swap and finds the most profitable pool. X -> Z -> Y or Y -> Z -> X on Pool<X, Z> -> Pool<Z, Y>
  * @param v_storage The storage object of the ipx::dex_volatile 
  * @param s_storage The storage object of the ipx::dex_stable 
  * @param vector_x A vector of several Coin<X> 
  * @param vector_y A vector of several Coin<Y> 
  * @param coin_x_amount The value the caller wishes to deposit for Coin<X> 
  * @param coin_y_amount The value the caller wishes to deposit for Coin<Y>
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  */
  entry public fun one_hop_swap<X, Y, Z>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    vector_x: vector<Coin<X>>,
    vector_y: vector<Coin<Y>>,
    coin_x_amount: u64,
    coin_y_amount: u64,
    coin_out_min_value: u64,
    ctx: &mut TxContext
  ) {

    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

    let (coin_x, coin_y) = router::one_hop_swap<X, Y, Z>(
      v_storage,
      s_storage,
      coin_x,
      coin_y,
      coin_out_min_value,
      ctx
    );

    destroy_zero_or_transfer(coin_x, ctx);
    destroy_zero_or_transfer(coin_y, ctx);
  }

  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It performs a three hop swap and finds the most profitable pool. X -> B1 -> B2 -> Y or Y -> B1 -> B2 -> X on Pool<X, Z> -> Pool<B1, B2> -> Pool<B2, Y>
  * @param v_storage The storage object of the ipx::dex_volatile 
  * @param s_storage The storage object of the ipx::dex_stable 
  * @param vector_x A vector of several Coin<X> 
  * @param vector_y A vector of several Coin<Y> 
  * @param coin_x_amount The value the caller wishes to deposit for Coin<X> 
  * @param coin_y_amount The value the caller wishes to deposit for Coin<Y>
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  */
  entry public fun two_hop_swap<X, Y, B1, B2>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    vector_x: vector<Coin<X>>,
    vector_y: vector<Coin<Y>>,
    coin_x_amount: u64,
    coin_y_amount: u64,
    coin_out_min_value: u64,
    ctx: &mut TxContext
  ) {

    // Create a coin from the vector. It keeps sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

    let (coin_x, coin_y) = router::two_hop_swap<X, Y, B1, B2>(
      v_storage,
      s_storage,
      coin_x,
      coin_y,
      coin_out_min_value,
      ctx
    );

    destroy_zero_or_transfer(coin_x, ctx);
    destroy_zero_or_transfer(coin_y, ctx);
  }

  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It adds liquidity to a Pool
  * @param v_storage The storage object of the ipx::dex_volatile 
  * @param s_storage The storage object of the ipx::dex_stable 
  * @param vector_x A vector of several Coin<X> 
  * @param vector_y A vector of several Coin<Y> 
  * @param coin_x_amount The value the caller wishes to deposit for Coin<X> 
  * @param coin_y_amount The value the caller wishes to deposit for Coin<Y>
  * @param is_volatile It indicates if it should add liquidity a stable or volatile pool
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  */
  entry public fun add_liquidity<X, Y>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    vector_x: vector<Coin<X>>,
    vector_y: vector<Coin<Y>>,
    coin_x_amount: u64,
    coin_y_amount: u64,
    is_volatile: bool,
    coin_min_amount: u64,
    ctx: &mut TxContext
  ) {

    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

    if (is_volatile) {
      if (are_coins_sorted<X, Y>()) {
        transfer::transfer(
          router::add_v_liquidity(
          v_storage,
          coin_x,
          coin_y,
          coin_min_amount,
          ctx
          ),
        tx_context::sender(ctx)
      )  
      } else {
        transfer::transfer(
          router::add_v_liquidity(
          v_storage,
          coin_y,
          coin_x,
          coin_min_amount,
          ctx
          ),
        tx_context::sender(ctx)
      )  
      }
      } else {
        if (are_coins_sorted<X, Y>()) {
          transfer::transfer(
            router::add_s_liquidity(
            s_storage,
            coin_x,
            coin_y,
            coin_min_amount,
            ctx
            ),
          tx_context::sender(ctx)
        )  
        } else {
          transfer::transfer(
            router::add_s_liquidity(
            s_storage,
            coin_x,
            coin_y,
            coin_min_amount,
            ctx
            ),
          tx_context::sender(ctx)
        )  
      }
    }
  }

  /**
  * @dev This function REQUIRES the coins to be sorted. It will send back any unused value. 
  * It removes liquidity from a volatile pool based on the shares
  * @param storage The storage object of the ipx::dex_volatile 
  * @param vector_lp_coin A vector of several VLPCoins
  * @param coin_amount_in The value the caller wishes to deposit for VLPCoins 
  * @param coin_x_min_amount The minimum amount of Coin<X> the user wishes to receive
  * @param coin_y_min_amount The minimum amount of Coin<Y> the user wishes to receive
  */
  entry public fun remove_v_liquidity<X, Y>(
    storage: &mut VStorage,
    vector_lp_coin: vector<Coin<VLPCoin<X, Y>>>,
    coin_amount_in: u64,
    coin_x_min_amount: u64,
    coin_y_min_amount: u64,
    ctx: &mut TxContext
  ){
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin = handle_coin_vector(vector_lp_coin, coin_amount_in, ctx);
    let sender = tx_context::sender(ctx);

    let (coin_x, coin_y) = volatile::remove_liquidity(
      storage,
      coin, 
      coin_x_min_amount,
      coin_y_min_amount,
      ctx
    );

    transfer::transfer(coin_x, sender);
    transfer::transfer(coin_y, sender);
  }

  /**
  * @dev This function REQUIRES the coins to be sorted. It will send back any unused value. 
  * It removes liquidity from a stable pool based on the shares
  * @param storage The storage object of the ipx::dex_volatile 
  * @param vector_lp_coin A vector of several SLPCoins
  * @param coin_amount_in The value the caller wishes to deposit for VLPCoins 
  * @param coin_x_min_amount The minimum amount of Coin<X> the user wishes to receive
  * @param coin_y_min_amount The minimum amount of Coin<Y> the user wishes to receive
  */
  entry public fun remove_s_liquidity<X, Y>(
    storage: &mut SStorage,
    vector_lp_coin: vector<Coin<SLPCoin<X, Y>>>,
    coin_amount_in: u64,
    coin_x_min_amount: u64,
    coin_y_min_amount: u64,
    ctx: &mut TxContext
  ){
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin = handle_coin_vector(vector_lp_coin, coin_amount_in, ctx);
    let sender = tx_context::sender(ctx);

    let (coin_x, coin_y) = stable::remove_liquidity(
      storage,
      coin, 
      coin_x_min_amount,
      coin_y_min_amount,
      ctx
    );

    transfer::transfer(coin_x, sender);
    transfer::transfer(coin_y, sender);
  }

/**
* @notice It allows a user to deposit a Coin<T> in a farm to earn Coin<IPX>. 
* @param storage The storage of the module ipx::ipx 
* @param accounts_storage The account storage of the module ipx::ipx 
* @param coin_vector A vector of Coin<T>
* @param coin_value The value of Coin<T> the caller wishes to deposit  
*/
  entry public fun stake<T>(
    storage: &mut IPXStorage,
    accounts_storage: &mut AccountStorage,
    coin_vector: vector<Coin<T>>,
    coin_value: u64,
    ctx: &mut TxContext
  ) {
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin = handle_coin_vector(coin_vector, coin_value, ctx);

    // Stake and send Coin<IPX> rewards to the caller.
    transfer::transfer(
      ipx::stake(
        storage,
        accounts_storage,
        coin,
        ctx
      ),
      tx_context::sender(ctx)
    );
  }

/**
* @notice It allows a user to withdraw an amount of Coin<T> from a farm. 
* @param storage The storage of the module ipx::ipx 
* @param accounts_storage The account storage of the module ipx::ipx 
* @param coin_value The amount of Coin<T> the caller wishes to withdraw
*/
  entry public fun unstake<T>(
    storage: &mut IPXStorage,
    accounts_storage: &mut AccountStorage,
    coin_value: u64,
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);
    // Unstake yields Coin<IPX> rewards.
    let (coin_ipx, coin) = ipx::unstake<T>(
        storage,
        accounts_storage,
        coin_value,
        ctx
    );
    transfer::transfer(coin_ipx, sender);
    transfer::transfer(coin, sender);
  }

/**
* @notice It allows a user to withdraw his/her rewards from a specific farm. 
* @param storage The storage of the module ipx::ipx 
* @param accounts_storage The account storage of the module ipx::ipx 
*/
  entry public fun get_rewards<T>(
    storage: &mut IPXStorage,
    accounts_storage: &mut AccountStorage,
    ctx: &mut TxContext   
  ) {
    transfer::transfer(ipx::get_rewards<T>(storage, accounts_storage, ctx) ,tx_context::sender(ctx));
  }

/**
* @notice It updates the Coin<T> farm rewards calculation.
* @param storage The storage of the module ipx::ipx 
*/
  entry public fun update_pool<T>(storage: &mut IPXStorage, ctx: &mut TxContext) {
    ipx::update_pool<T>(storage, ctx);
  }

/**
* @notice It updates all pools.
* @param storage The storage of the module ipx::ipx 
*/
  entry public fun update_all_pools(storage: &mut IPXStorage, ctx: &mut TxContext) {
    ipx::update_all_pools(storage, ctx);
  }

/**
* @notice It allows a user to burn Coin<IPX>.
* @param storage The storage of the module ipx::ipx 
* @param coin_vector A vector of Coin<IPX>
* @param coin_value The value of Coin<IPX> the caller wishes to burn 
*/
  entry public fun burn_ipx(
    storage: &mut IPXStorage,
    coin_vector: vector<Coin<IPX>>,
    coin_value: u64,
    ctx: &mut TxContext
  ) {
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    ipx::burn_ipx(storage, handle_coin_vector(coin_vector, coin_value, ctx));
  }
}