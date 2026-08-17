//! Configuration read from the environment. Every variable in .env.example
//! that a service reads is read here, in one place, so nothing drifts.

use anyhow::Context;

#[derive(Clone, Debug)]
pub struct Config {
    pub bsc_rpc_http: String,
    pub bsc_rpc_http_fallback: Option<String>,
    pub bsc_testnet_rpc_http: Option<String>,
    pub chain_id: u64,
    pub identity_registry: String,
    pub reputation_registry: String,
    pub agentic_commerce: String,
    pub hire_rail: Option<String>,
    pub trust_snapshot: Option<String>,
    pub database_url: String,
    pub ipfs_gateway: String,
    pub ipfs_gateway_fallback: Option<String>,
    pub graph_api_key: Option<String>,
    pub probe_concurrency: usize,
    pub probe_interval_secs: u64,
    pub bscscan_api_key: Option<String>,
    pub api_port: u16,
}

fn required(name: &str) -> anyhow::Result<String> {
    std::env::var(name).with_context(|| format!("{name} is not set"))
}

fn optional(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

impl Config {
    /// Load from the environment. Fails loudly on anything missing or
    /// malformed rather than defaulting silently.
    pub fn from_env() -> anyhow::Result<Self> {
        Ok(Self {
            bsc_rpc_http: required("BSC_RPC_HTTP")?,
            bsc_rpc_http_fallback: optional("BSC_RPC_HTTP_FALLBACK"),
            bsc_testnet_rpc_http: optional("BSC_TESTNET_RPC_HTTP"),
            chain_id: required("CHAIN_ID")?.parse().context("CHAIN_ID")?,
            identity_registry: required("IDENTITY_REGISTRY")?,
            reputation_registry: required("REPUTATION_REGISTRY")?,
            agentic_commerce: required("AGENTIC_COMMERCE")?,
            hire_rail: optional("HIRE_RAIL"),
            trust_snapshot: optional("TRUST_SNAPSHOT"),
            database_url: required("DATABASE_URL")?,
            ipfs_gateway: required("IPFS_GATEWAY")?,
            ipfs_gateway_fallback: optional("IPFS_GATEWAY_FALLBACK"),
            graph_api_key: optional("GRAPH_API_KEY"),
            probe_concurrency: required("PROBE_CONCURRENCY")?
                .parse()
                .context("PROBE_CONCURRENCY")?,
            probe_interval_secs: required("PROBE_INTERVAL_SECS")?
                .parse()
                .context("PROBE_INTERVAL_SECS")?,
            bscscan_api_key: optional("BSCSCAN_API_KEY"),
            api_port: required("API_PORT")?.parse().context("API_PORT")?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn optional_treats_empty_as_missing() {
        std::env::set_var("TEST_EMPTY_VAR", "");
        assert_eq!(optional("TEST_EMPTY_VAR"), None);
        std::env::remove_var("TEST_EMPTY_VAR");
    }

    #[test]
    fn required_fails_when_missing() {
        std::env::remove_var("TEST_MISSING_VAR");
        assert!(required("TEST_MISSING_VAR").is_err());
    }
}
