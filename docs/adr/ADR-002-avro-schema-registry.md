# ADR-002: Avro + Confluent Schema Registry for Kafka messages

**Date:** 2025-06  
**Status:** Accepted

## Decision
All Kafka messages use Avro serialization with Confluent Schema Registry.
Plain JSON Kafka messages are not permitted.

## Alternatives rejected
- **JSON without schema**: No schema enforcement; producer/consumer coupling breaks silently; no backward compatibility checking.
- **Protobuf**: Team has existing Avro experience; Confluent Schema Registry has first-class Avro support; ecosystem tooling is mature.

## Consequences
- `common-events` module owns all `.avsc` files.
- BACKWARD compatibility mode enforced — all new fields must have defaults.
- CI registers schemas before any deployment.
- `avro-validate.sh` hook enforces defaults at edit time.
