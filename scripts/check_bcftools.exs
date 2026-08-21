case System.find_executable("bcftools") do
  nil ->
    IO.puts("bcftools not found; conformance cross-check skipped")

  executable ->
    source =
      "##fileformat=VCFv4.5\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\nchr1\t1\t.\tA\tC\t.\tPASS\t.\n"

    document = VCF.parse!(source)
    path = Path.join(System.tmp_dir!(), "vcf-bcftools-#{System.unique_integer([:positive])}.vcf")

    try do
      :ok = File.write(path, VCF.encode!(document))
      {_output, 0} = System.cmd(executable, ["view", "-Ov", path], stderr_to_stdout: true)
      IO.puts("bcftools accepted representative encoded VCF")
    after
      File.rm(path)
    end
end
