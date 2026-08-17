//! Agent card resolution and parsing. A card is the JSON behind tokenURI:
//! either the ERC-8004 registration shape (services list) or an A2A agent
//! card (url plus skills). We record what resolved and what is missing.

use serde_json::Value;

/// Parsed essentials from a card, however partial.
#[derive(Debug, Default)]
pub struct ParsedCard {
    pub name: Option<String>,
    pub description: Option<String>,
    /// [{kind, url}] built from services / endpoints / url fields.
    pub endpoints: Vec<(String, String)>,
    pub skills: Option<Value>,
    pub trust_models: Vec<String>,
}

/// Endpoint kind classification, SPEC.md Section 12: a web profile page is
/// not an agent service. The strict live count uses `service` only.
pub fn classify_endpoint(name: &str, url: &str) -> &'static str {
    let n = name.to_ascii_lowercase();
    if n.contains("a2a")
        || n.contains("mcp")
        || n.contains("api")
        || n.contains("8183")
        || n.contains("agent") && n.contains("card")
    {
        return "service";
    }
    if n == "web" || n.contains("website") || n.contains("profile") || n.contains("homepage") {
        return "web";
    }
    let u = url.to_ascii_lowercase();
    if u.contains("/api/")
        || u.contains("/.well-known/")
        || u.contains("/mcp")
        || u.contains("/a2a")
    {
        "service"
    } else {
        "unknown"
    }
}

pub fn parse_card(bytes: &[u8]) -> Result<ParsedCard, &'static str> {
    let value: Value = serde_json::from_slice(bytes).map_err(|_| "invalid_json")?;
    let obj = value.as_object().ok_or("invalid_json")?;
    let mut card = ParsedCard {
        name: obj.get("name").and_then(|v| v.as_str()).map(str::to_owned),
        description: obj
            .get("description")
            .and_then(|v| v.as_str())
            .map(str::to_owned),
        ..Default::default()
    };

    // ERC-8004 registration shape: services: [{name, endpoint}].
    if let Some(services) = obj.get("services").and_then(|v| v.as_array()) {
        for s in services {
            let name = s.get("name").and_then(|v| v.as_str()).unwrap_or("");
            if let Some(endpoint) = s.get("endpoint").and_then(|v| v.as_str()) {
                if endpoint.starts_with("http") {
                    card.endpoints.push((
                        classify_endpoint(name, endpoint).to_owned(),
                        endpoint.to_owned(),
                    ));
                }
            }
        }
    }
    // Alternative shape: endpoints: [{kind|name, url}] or plain strings.
    if let Some(endpoints) = obj.get("endpoints").and_then(|v| v.as_array()) {
        for e in endpoints {
            match e {
                Value::String(url) if url.starts_with("http") => {
                    card.endpoints
                        .push((classify_endpoint("", url).to_owned(), url.clone()));
                }
                Value::Object(map) => {
                    let kind = map
                        .get("kind")
                        .or_else(|| map.get("name"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    if let Some(url) = map.get("url").and_then(|v| v.as_str()) {
                        if url.starts_with("http") {
                            card.endpoints
                                .push((classify_endpoint(kind, url).to_owned(), url.to_owned()));
                        }
                    }
                }
                _ => {}
            }
        }
    }
    // A2A card shape: a top level url is the service endpoint.
    if let Some(url) = obj.get("url").and_then(|v| v.as_str()) {
        if url.starts_with("http") {
            card.endpoints.push(("service".to_owned(), url.to_owned()));
        }
    }
    card.endpoints.dedup_by(|a, b| a.1 == b.1);

    if let Some(skills) = obj.get("skills") {
        card.skills = Some(skills.clone());
    }
    for key in ["trustModels", "supportedTrusts", "trust_models"] {
        if let Some(models) = obj.get(key).and_then(|v| v.as_array()) {
            card.trust_models = models
                .iter()
                .filter_map(|m| m.as_str().map(str::to_owned))
                .collect();
        }
    }
    Ok(card)
}

/// Decode a data: URI card without touching the network.
pub fn decode_data_uri(uri: &str) -> Option<Vec<u8>> {
    use base64::Engine;
    let rest = uri.strip_prefix("data:")?;
    let (meta, payload) = rest.split_once(',')?;
    if meta.contains(";base64") {
        base64::engine::general_purpose::STANDARD
            .decode(payload.trim())
            .ok()
            .or_else(|| {
                base64::engine::general_purpose::URL_SAFE
                    .decode(payload.trim())
                    .ok()
            })
    } else {
        // Percent decoded plain JSON.
        Some(
            url::form_urlencoded::parse(format!("x={payload}").as_bytes())
                .next()
                .map(|(_, v)| v.into_owned().into_bytes())
                .unwrap_or_else(|| payload.as_bytes().to_vec()),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_registration_v1_shape() {
        // Shape observed on chain from agent 120235, 17 Aug 2026.
        let body = br#"{"type":"https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
            "name":"Nghia2887","description":"An EvoEvo AI Agent focused on crypto.",
            "services":[{"name":"web","endpoint":"https://evoevo.ai/agent/detail?id=169295"}]}"#;
        let card = parse_card(body).unwrap();
        assert_eq!(card.name.as_deref(), Some("Nghia2887"));
        assert_eq!(card.endpoints.len(), 1);
        assert_eq!(card.endpoints[0].0, "web");
    }

    #[test]
    fn classifies_service_endpoints() {
        assert_eq!(classify_endpoint("a2a", "https://x.ai/agent"), "service");
        assert_eq!(classify_endpoint("", "https://x.ai/api/v1"), "service");
        assert_eq!(classify_endpoint("web", "https://x.ai/"), "web");
    }

    #[test]
    fn decodes_base64_data_uri() {
        let uri = "data:application/json;base64,eyJuYW1lIjoiVGVzdCJ9";
        let bytes = decode_data_uri(uri).unwrap();
        let card = parse_card(&bytes).unwrap();
        assert_eq!(card.name.as_deref(), Some("Test"));
    }

    #[test]
    fn rejects_non_json() {
        assert!(parse_card(b"<html>not json</html>").is_err());
    }
}
