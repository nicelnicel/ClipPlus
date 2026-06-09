use serde::{Deserialize, Serialize};

pub const REDACTED_ID_PREFIX_CHARS: usize = 8;
const REDACTED_VALUE: &str = "<redacted>";
const SENSITIVE_FIELD_NAMES: [&str; 3] = ["shared_key", "token", "key"];

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RedactedConfig {
    pub shared_key_configured: bool,
    pub group_id_prefix: String,
    pub device_id_prefix: String,
    pub trusted_peer_count: usize,
    pub paused_peer_count: usize,
}

pub fn redact_config(
    shared_key_configured: bool,
    _raw_key: &str,
    group_id: &str,
    device_id: &str,
    trusted_peer_count: usize,
    paused_peer_count: usize,
) -> RedactedConfig {
    RedactedConfig {
        shared_key_configured,
        group_id_prefix: prefix(group_id),
        device_id_prefix: prefix(device_id),
        trusted_peer_count,
        paused_peer_count,
    }
}

fn prefix(value: &str) -> String {
    value.chars().take(REDACTED_ID_PREFIX_CHARS).collect()
}

pub fn redact_sensitive_text(text: &str) -> String {
    let mut redacted = String::with_capacity(text.len());
    let mut cursor = 0;

    while cursor < text.len() {
        if let Some(found) = find_next_sensitive_value(text, cursor) {
            redacted.push_str(&text[cursor..found.value_start]);
            redacted.push_str(REDACTED_VALUE);
            cursor = found.value_end;
        } else {
            redacted.push_str(&text[cursor..]);
            break;
        }
    }

    redacted
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct SensitiveValue {
    value_start: usize,
    value_end: usize,
}

fn find_next_sensitive_value(text: &str, start: usize) -> Option<SensitiveValue> {
    let mut cursor = start;

    while cursor < text.len() {
        if let Some(found) = parse_sensitive_value(text, cursor) {
            return Some(found);
        }

        cursor += char_at(text, cursor)?.len_utf8();
    }

    None
}

fn parse_sensitive_value(text: &str, start: usize) -> Option<SensitiveValue> {
    let first = char_at(text, start)?;
    let (field_start, field_quote) = if is_quote(first) {
        (start + first.len_utf8(), Some(first))
    } else {
        if start > 0 && previous_char(text, start).is_some_and(is_identifier_char) {
            return None;
        }
        (start, None)
    };

    for field_name in SENSITIVE_FIELD_NAMES {
        if let Some(found) = parse_field_value(text, field_start, field_quote, field_name) {
            return Some(found);
        }
    }

    None
}

fn parse_field_value(
    text: &str,
    field_start: usize,
    field_quote: Option<char>,
    field_name: &str,
) -> Option<SensitiveValue> {
    let field_end = field_start.checked_add(field_name.len())?;
    let candidate = text.get(field_start..field_end)?;
    if !candidate.eq_ignore_ascii_case(field_name) {
        return None;
    }

    let mut cursor = field_end;
    if let Some(quote) = field_quote {
        if char_at(text, cursor)? != quote {
            return None;
        }
        cursor += quote.len_utf8();
    } else if char_at(text, cursor).is_some_and(is_identifier_char) {
        return None;
    }

    cursor = skip_whitespace(text, cursor);
    if !matches!(char_at(text, cursor), Some('=') | Some(':')) {
        return None;
    }
    cursor += 1;
    cursor = skip_whitespace(text, cursor);

    let value_quote = char_at(text, cursor).filter(|ch| is_quote(*ch));
    if let Some(quote) = value_quote {
        cursor += quote.len_utf8();
    }

    if cursor >= text.len() {
        return None;
    }

    let value_end = find_value_end(text, cursor, value_quote);
    if value_end == cursor {
        return None;
    }

    Some(SensitiveValue {
        value_start: cursor,
        value_end,
    })
}

fn find_value_end(text: &str, start: usize, value_quote: Option<char>) -> usize {
    let mut cursor = start;

    while cursor < text.len() {
        let Some(ch) = char_at(text, cursor) else {
            break;
        };

        let is_end = if let Some(quote) = value_quote {
            ch == quote
        } else {
            is_unquoted_value_terminator(ch)
        };

        if is_end {
            break;
        }

        cursor += ch.len_utf8();
    }

    cursor
}

fn skip_whitespace(text: &str, start: usize) -> usize {
    let mut cursor = start;

    while cursor < text.len() {
        let Some(ch) = char_at(text, cursor) else {
            break;
        };
        if !ch.is_whitespace() {
            break;
        }
        cursor += ch.len_utf8();
    }

    cursor
}

fn char_at(text: &str, index: usize) -> Option<char> {
    text.get(index..)?.chars().next()
}

fn previous_char(text: &str, index: usize) -> Option<char> {
    text.get(..index)?.chars().next_back()
}

fn is_identifier_char(ch: char) -> bool {
    ch.is_ascii_alphanumeric() || ch == '_'
}

fn is_quote(ch: char) -> bool {
    matches!(ch, '"' | '\'')
}

fn is_unquoted_value_terminator(ch: char) -> bool {
    ch.is_whitespace() || matches!(ch, ',' | ';' | '&' | '"' | '\'')
}
