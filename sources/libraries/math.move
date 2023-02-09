module ipx::math {

  public fun mul_div(x: u64, y: u64, z: u64): u64 {
    (((x as u256) * (y as u256)) / (z as u256) as u64)
  }

  public fun sqrt_u256(y: u256): u256 {
        let z = 0;
        if (y > 3) {
            z = y;
            let x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        };
        z
    }
}