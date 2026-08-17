//! Guarded HTTP fetching for agent cards and endpoints. Redirects are
//! followed manually so every hop passes the SSRF guard. SPEC.md Section 12.

use anyhow::Context;
use std::net::IpAddr;
use std::time::Duration;
use url::Url;

pub const USER_AGENT: &str = "TrustList/0.1 (+https://github.com/big14way/Trustlist)";
const MAX_REDIRECTS: usize = 3;
const MAX_BODY: usize = 512 * 1024;

/// Why a fetch failed, recorded verbatim in probe history.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum FailureKind {
    Dns,
    Tls,
    Timeout,
    ConnRefused,
    HttpError,
    BadBody,
    PrivateBlocked,
    BadUrl,
    TooManyRedirects,
}

impl FailureKind {
    pub fn as_str(self) -> &'static str {
        match self {
            FailureKind::Dns => "dns",
            FailureKind::Tls => "tls",
            FailureKind::Timeout => "timeout",
            FailureKind::ConnRefused => "conn_refused",
            FailureKind::HttpError => "http_error",
            FailureKind::BadBody => "bad_body",
            FailureKind::PrivateBlocked => "private_blocked",
            FailureKind::BadUrl => "bad_url",
            FailureKind::TooManyRedirects => "too_many_redirects",
        }
    }
}

pub struct FetchResult {
    pub status: u16,
    pub body: Vec<u8>,
}

/// True when the address must never be contacted: loopback, private ranges,
/// link local, and unique local addresses.
fn is_private(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            v4.is_loopback()
                || v4.is_private()
                || v4.is_link_local()
                || v4.is_unspecified()
                || v4.is_broadcast()
        }
        IpAddr::V6(v6) => {
            v6.is_loopback()
                || v6.is_unspecified()
                // Unique local fc00::/7 and link local fe80::/10.
                || (v6.segments()[0] & 0xfe00) == 0xfc00
                || (v6.segments()[0] & 0xffc0) == 0xfe80
        }
    }
}

/// Resolve the host and reject any URL whose addresses include a private
/// range. Returns Err(kind) rather than anyhow so callers can record it.
async fn guard_url(url: &Url) -> Result<(), FailureKind> {
    if url.scheme() != "https" && url.scheme() != "http" {
        return Err(FailureKind::BadUrl);
    }
    let host = url.host_str().ok_or(FailureKind::BadUrl)?.to_string();
    let port = url.port_or_known_default().unwrap_or(443);
    let addrs = tokio::net::lookup_host((host.as_str(), port))
        .await
        .map_err(|_| FailureKind::Dns)?;
    let mut any = false;
    for addr in addrs {
        any = true;
        if is_private(addr.ip()) {
            return Err(FailureKind::PrivateBlocked);
        }
    }
    if !any {
        return Err(FailureKind::Dns);
    }
    Ok(())
}

pub fn build_client() -> anyhow::Result<reqwest::Client> {
    reqwest::Client::builder()
        .user_agent(USER_AGENT)
        .connect_timeout(Duration::from_secs(4))
        .timeout(Duration::from_secs(8))
        // Redirects are followed manually through the SSRF guard.
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .context("building http client")
}

fn classify(e: &reqwest::Error) -> FailureKind {
    if e.is_timeout() {
        FailureKind::Timeout
    } else if e.is_connect() {
        let msg = format!("{e:?}").to_lowercase();
        if msg.contains("certificate") || msg.contains("tls") || msg.contains("ssl") {
            FailureKind::Tls
        } else if msg.contains("refused") {
            FailureKind::ConnRefused
        } else {
            FailureKind::Dns
        }
    } else {
        FailureKind::HttpError
    }
}

/// GET a URL with the guard applied to every redirect hop. Any HTTP status
/// is returned as Ok; transport failures come back as Err(kind).
pub async fn guarded_get(client: &reqwest::Client, url: &str) -> Result<FetchResult, FailureKind> {
    let mut current: Url = url.parse().map_err(|_| FailureKind::BadUrl)?;
    for _ in 0..=MAX_REDIRECTS {
        guard_url(&current).await?;
        let resp = client
            .get(current.clone())
            .send()
            .await
            .map_err(|e| classify(&e))?;
        let status = resp.status();
        if status.is_redirection() {
            let location = resp
                .headers()
                .get(reqwest::header::LOCATION)
                .and_then(|v| v.to_str().ok())
                .ok_or(FailureKind::HttpError)?;
            current = current.join(location).map_err(|_| FailureKind::BadUrl)?;
            continue;
        }
        let mut body = Vec::new();
        let mut stream = resp;
        while let Some(chunk) = stream.chunk().await.map_err(|_| FailureKind::BadBody)? {
            if body.len() + chunk.len() > MAX_BODY {
                body.extend_from_slice(&chunk[..MAX_BODY - body.len()]);
                break;
            }
            body.extend_from_slice(&chunk);
        }
        return Ok(FetchResult {
            status: status.as_u16(),
            body,
        });
    }
    Err(FailureKind::TooManyRedirects)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn private_ranges_are_blocked() {
        for ip in [
            "127.0.0.1",
            "10.1.2.3",
            "172.16.0.1",
            "192.168.1.1",
            "169.254.0.1",
            "0.0.0.0",
        ] {
            assert!(is_private(ip.parse().unwrap()), "{ip} should be private");
        }
        assert!(is_private("::1".parse().unwrap()));
        assert!(is_private("fc00::1".parse().unwrap()));
        assert!(is_private("fe80::1".parse().unwrap()));
    }

    #[test]
    fn public_addresses_pass() {
        for ip in ["8.8.8.8", "104.18.0.1", "2606:4700::1111"] {
            assert!(!is_private(ip.parse().unwrap()), "{ip} should be public");
        }
    }

    #[tokio::test]
    async fn guard_rejects_localhost_url() {
        let url: Url = "http://127.0.0.1:8080/x".parse().unwrap();
        assert_eq!(
            guard_url(&url).await.unwrap_err(),
            FailureKind::PrivateBlocked
        );
    }

    #[tokio::test]
    async fn guard_rejects_non_http_scheme() {
        let url: Url = "file:///etc/passwd".parse().unwrap();
        assert_eq!(guard_url(&url).await.unwrap_err(), FailureKind::BadUrl);
    }
}
