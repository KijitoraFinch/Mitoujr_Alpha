use serde_json::Value;

pub const MAXIMUM_SAFE_INTEGER: i64 = 9_007_199_254_740_991;
pub const MINIMUM_SAFE_INTEGER: i64 = -MAXIMUM_SAFE_INTEGER;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum IntegerDomain {
    Signed,
    Nonnegative,
}

pub fn decode_protocol_integer(value: &Value, domain: IntegerDomain) -> Option<i64> {
    let value = value.as_i64()?;
    let valid = match domain {
        IntegerDomain::Signed => (MINIMUM_SAFE_INTEGER..=MAXIMUM_SAFE_INTEGER).contains(&value),
        IntegerDomain::Nonnegative => (0..=MAXIMUM_SAFE_INTEGER).contains(&value),
    };
    valid.then_some(value)
}

#[cfg(test)]
mod tests {
    use super::{decode_protocol_integer, IntegerDomain};
    use serde::Deserialize;
    use serde_json::Value;

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase", deny_unknown_fields)]
    struct Case {
        id: String,
        domain: String,
        value: Value,
        valid: bool,
    }

    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Utf8Case {
        id: String,
        hex: String,
        valid: bool,
    }

    fn bytes_of_hex(value: &str) -> Vec<u8> {
        assert!(value.len().is_multiple_of(2), "hex value has odd length");
        value
            .as_bytes()
            .chunks_exact(2)
            .map(|pair| {
                let digits = std::str::from_utf8(pair).expect("ASCII hex pair");
                u8::from_str_radix(digits, 16).expect("lowercase hex byte")
            })
            .collect()
    }

    #[test]
    fn shared_protocol_integer_corpus() {
        let corpus = include_str!("../../spec/protocol-integers.json");
        let cases: Vec<Case> = serde_json::from_str(corpus).expect("valid integer corpus JSON");
        for case in cases {
            let domain = match case.domain.as_str() {
                "signed" => IntegerDomain::Signed,
                "nonnegative" => IntegerDomain::Nonnegative,
                other => panic!("{}: unknown integer domain: {other}", case.id),
            };
            assert_eq!(
                decode_protocol_integer(&case.value, domain).is_some(),
                case.valid,
                "{}",
                case.id
            );
        }
    }

    #[test]
    fn shared_utf8_corpus() {
        let corpus = include_str!("../../spec/utf8.json");
        let cases: Vec<Utf8Case> = serde_json::from_str(corpus).expect("valid UTF-8 corpus JSON");
        for case in cases {
            assert_eq!(
                std::str::from_utf8(&bytes_of_hex(&case.hex)).is_ok(),
                case.valid,
                "{}",
                case.id
            );
        }
    }
}
