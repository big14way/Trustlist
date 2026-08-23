//! sqlx::migrate! embeds the migrations directory at compile time, but cargo
//! does not know that a new .sql file should trigger a rebuild. Without this
//! the binaries keep an older set embedded and refuse to start with
//! "migration N was previously applied but is missing in the resolved
//! migrations", which is a confusing way to learn you have a stale build.
fn main() {
    println!("cargo:rerun-if-changed=../../migrations");
}
