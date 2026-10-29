## Test double: an IndustrialMarketBenchmark whose build always fails, for the review scene's recovery path.
extends IndustrialMarketBenchmark


func build() -> bool:
	errors.append("forced benchmark failure")
	return false
