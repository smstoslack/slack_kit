junit_dir = Path.expand("../cover", __DIR__)
File.mkdir_p!(junit_dir)
Application.put_env(:junit_formatter, :report_dir, junit_dir)
Application.put_env(:junit_formatter, :report_file, "junit.xml")

ExUnit.start(formatters: [JUnitFormatter, ExUnit.CLIFormatter])
