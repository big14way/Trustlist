//! Typed bindings for the registry events we index. The signatures come from
//! the Sourcify verified implementations, vendored in crates/indexer/abi/.
//! See docs/VERIFICATION.md section 2 for the topic0 hashes.

use alloy::sol;

sol! {
    #[derive(Debug)]
    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);

    #[derive(Debug)]
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);

    #[derive(Debug)]
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    #[derive(Debug)]
    event NewFeedback(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64 feedbackIndex,
        int128 value,
        uint8 valueDecimals,
        string indexed indexedTag1,
        string tag1,
        string tag2,
        string endpoint,
        string feedbackURI,
        bytes32 feedbackHash
    );

    #[derive(Debug)]
    event FeedbackRevoked(uint256 indexed agentId, address indexed clientAddress, uint64 indexed feedbackIndex);
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloy::sol_types::SolEvent;

    // The topic0 hashes recovered from the verified source on 17 Aug 2026.
    // If a binding drifts from the real ABI these fail loudly.
    #[test]
    fn registered_topic0_matches_chain() {
        assert_eq!(
            format!("0x{}", alloy::hex::encode(Registered::SIGNATURE_HASH)),
            "0xca52e62c367d81bb2e328eb795f7c7ba24afb478408a26c0e201d155c449bc4a" // event topic0 hash
        );
    }

    #[test]
    fn new_feedback_topic0_matches_chain() {
        assert_eq!(
            format!("0x{}", alloy::hex::encode(NewFeedback::SIGNATURE_HASH)),
            "0x6a4a61743519c9d648a14e6493f47dbe3ff1aa29e7785c96c8326a205e58febc" // event topic0 hash
        );
    }
}
