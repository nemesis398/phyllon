//! The security headers every response carries.

/// The header names and values set on every response, including errors.
///
/// The content security policy allows only the site's own resources and
/// forbids framing. HSTS has no `includeSubDomains`, because a deployer's
/// other subdomains are not Phyllon's to decide.
pub const SECURITY_HEADERS: [(&str, &str); 5] = [
    (
        "Content-Security-Policy",
        "default-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
    ),
    ("X-Content-Type-Options", "nosniff"),
    ("Referrer-Policy", "no-referrer"),
    ("Strict-Transport-Security", "max-age=31536000"),
    (
        "Permissions-Policy",
        "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
    ),
];
