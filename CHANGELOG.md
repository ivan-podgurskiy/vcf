# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-22

### Added

- Pure-Elixir parsing and canonical writing for VCF 4.1 through 4.5.
- Typed headers, records, fields, samples, and arbitrary-ploidy genotypes.
- Explicit version profiles with type, cardinality, allele, and phasing validation.
- Strict and permissive modes with machine-readable errors and warnings.
- Bounded-memory streams for paths, I/O devices, and one-shot enumerables.
- Sequential plain, gzip, and concatenated BGZF input plus gzip output.
- Stable metadata, INFO, FORMAT, sample, record, and alternate-allele ordering.
- Property, version-fixture, robustness, and million-record streaming coverage.

[1.0.0]: https://github.com/ivan-podgurskiy/vcf/releases/tag/v1.0.0
