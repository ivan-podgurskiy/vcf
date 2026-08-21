# VCF

[![Hex.pm](https://img.shields.io/hexpm/v/vcf.svg)](https://hex.pm/packages/vcf)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/vcf)
[![License](https://img.shields.io/hexpm/l/vcf.svg)](LICENSE)

`vcf` is a pure-Elixir parser, validator, streaming reader, and writer for
Variant Call Format 4.1–4.5. It has no runtime dependencies, NIFs, or required
system tools.

Correctness is the first priority. The package keeps the declared VCF version
explicit, represents core concepts with typed structs, preserves source order,
and returns machine-readable diagnostics.

## Installation

Add `vcf` to `mix.exs`:

```elixir
def deps do
  [
    {:vcf, "~> 1.0"}
  ]
end
```

## Quick start

`VCF.parse/2` treats a binary as content, never as a path:

```elixir
source = """
##fileformat=VCFv4.5
##INFO=<ID=DP,Number=1,Type=Integer,Description="Depth">
#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
chr1\t10\trs1\tA\tC\t42\tPASS\tDP=9
"""

{:ok, document} = VCF.parse(source)
[record] = document.records

record.chrom                         # => "chr1"
record.pos                           # => 10
VCF.Field.get(record.info, "DP")    # => 9
```

Use `VCF.read/2` for a complete file and `VCF.stream/2` for lazy records:

```elixir
{:ok, document} = VCF.read("variants.vcf.gz")
{:ok, stream} = VCF.stream("variants.vcf.gz")
```

Bang variants raise `VCF.ParseError`:

```elixir
document = VCF.read!("variants.vcf")
stream = VCF.stream!("variants.vcf")
```

## Streaming large files

The header is parsed eagerly and exposed as `stream.header`. Records are parsed
on demand, so normal path processing retains only the header, current record,
and bounded I/O buffers:

```elixir
VCF.stream!("cohort.vcf.gz")
|> Stream.filter(&(&1.chrom == "chr1"))
|> Enum.take(100)
```

Path-backed streams reopen safely for each enumeration. Caller-owned I/O
devices and generic enumerables are one-shot; the library never closes a
device it did not open.

The default maximum physical line size is 64 MiB. Override it with
`max_line_bytes:` when unusually wide sample records require it.

## Strict and permissive modes

Strict mode is the default and stops on a specification violation:

```elixir
VCF.read("variants.vcf", mode: :strict)
```

Permissive mode retains recoverable invalid values in `VCF.Field.raw` and adds
structured `%VCF.Warning{}` values to the header, record, and collected
document:

```elixir
{:ok, document} = VCF.read("producer-output.vcf", mode: :permissive)
document.warnings
```

Unsupported versions, missing structural header lines, unreadable compression,
and record boundaries that cannot be determined remain errors in both modes.

## Genotypes and samples

`GT` is represented by `%VCF.Genotype{}` rather than an opaque string:

```elixir
{:ok, genotype} = VCF.Genotype.parse("|0|0/1/2")

genotype.alleles
# => [0, 0, 1, 2]

genotype.phasing
# => [:phased, :phased, :unphased, :unphased]
```

Arbitrary ploidy, haploid calls, missing alleles, mixed partial phasing, and
different sample ploidies are retained. Samples and FORMAT values stay in
source order.

## Validation

Parsed streams validate records against their declared header and version.
Programmatically created documents can be checked independently:

```elixir
case VCF.validate(document) do
  :ok -> :valid
  {:error, errors} -> {:invalid, errors}
end
```

Validation covers header definitions, fixed columns, declared INFO/FORMAT and
FILTER fields, VCF types, fixed and symbolic cardinalities, genotype allele
bounds and ploidy, symbolic alleles, spanning deletions, and all four breakend
orientations. Errors are `%VCF.Error{}` structs with fields such as `line`,
`field`, `key`, `value`, and `reason`.

## Transforming and writing

Stream transformations preserve header context:

```elixir
VCF.stream!("input.vcf.gz")
|> VCF.filter(&(&1.chrom == "chr1"))
|> VCF.write!("chr1.vcf.gz")
```

Documents can use destination-first form:

```elixir
:ok = VCF.write("output.vcf", document)
encoded = VCF.encode!(document)
```

The writer accepts plain and `.gz` paths and caller-owned I/O devices. It
validates by default and writes record enumerables incrementally. Pass
`validate: false` only for already trusted structures. `compression: :gzip`
forces gzip output independently of a path suffix.

Programmatic construction uses the public structs:

```elixir
header = %VCF.Header{
  version: %VCF.Version{major: 4, minor: 5},
  metadata: [],
  columns: [:chrom, :pos, :id, :ref, :alt, :qual, :filter, :info]
}

record = %VCF.Record{
  chrom: "chr1",
  pos: 10,
  ref: "A",
  alt: ["C"],
  filter: :pass
}

:ok = VCF.write("constructed.vcf", header, [record])
```

## Compression

Input compression is detected from its signature rather than trusted solely
from a filename. Plain VCF, gzip, and concatenated BGZF blocks are decoded
sequentially with Erlang/OTP `:zlib`. Gzip output is supported; BGZF output,
virtual offsets, Tabix, and CSI indexes are outside 1.0.

## Supported versions

The declared `##fileformat` selects one explicit profile:

| Version | Notable supported differences |
| --- | --- |
| 4.1 | `A`, `G`, and variable cardinality; no spanning-deletion `*` |
| 4.2 | `Number=R`, trailing INFO attributes, and `*` |
| 4.3 | UTF-8/CRLF, percent escapes, `META`, `<*>`, unique IDs, and 32-bit values |
| 4.4 | `Number=P`, partial phasing, and revised structural-variant declarations |
| 4.5 | `LA`/`LR`/`LG`/`M`, local alleles, and `<NON_REF>` |

VCF 3.x and unknown 4.x versions return `:unsupported_version`; there is no
silent fallback to the newest profile.

## Round-trip guarantees

The package preserves metadata order, unknown metadata, record order, alternate
allele order, INFO/FORMAT order, sample order, and typed genotype semantics.
Canonical writing may normalize quoting, escaped values, numeric spelling, and
line endings. Byte-for-byte identity is not guaranteed.

## Security, limits, and non-goals

Input IDs and keys remain binaries. Parsers convert only a closed set of known
tokens to atoms and never call `String.to_atom/1` on source data. Compressed data
uses bounded incremental inflation and physical lines have a configurable size
limit.

Version 1.0 intentionally does not provide BCF, FASTA-backed validation,
variant normalization, medical interpretation, annotation databases, indexes,
random regional lookup, or a CLI.

## Development

```shell
mix deps.get
mix test
mix format --check-formatted
mix credo --strict
mix dialyzer --format github
mix docs --warnings-as-errors
mix hex.build
```

`mix run scripts/check_bcftools.exs` performs an optional development-only
cross-check and exits successfully with an explicit skip when `bcftools` is not
installed.

## License

MIT. See [LICENSE](LICENSE).
