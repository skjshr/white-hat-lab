extends "res://tests/test_investigation_models.gd"
# The operations regression now exercises observed data and concrete recovery,
# replacing the retired fixed action/flag solver.
func run() -> void:
	hunt(); network(); recovery(); migration()
	print("ADVANCED_OPERATIONS_", "PASS" if failures.is_empty() else "FAIL", " assertions=", assertions)
	quit(0 if failures.is_empty() else 1)
