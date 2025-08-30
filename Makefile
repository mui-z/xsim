format:
	# Prefer local SwiftFormat CLI if available
	@if command -v swiftformat >/dev/null 2>&1; then \
		echo "Running SwiftFormat (CLI)"; \
		swiftformat --config .swiftformat . || true; \
	else \
		# Try SPM command plugin if configured
		if command -v swift >/dev/null 2>&1; then \
			if swift package plugin --list 2>/dev/null | grep -qi swiftformat; then \
				echo "Running SwiftFormat (SPM plugin: swiftformat)"; \
				swift package --allow-writing-to-package-directory plugin swiftformat || \
				( echo "Trying alternative plugin name (SwiftFormatPlugin)"; swift package --allow-writing-to-package-directory plugin SwiftFormatPlugin ) || true; \
			else \
				echo "SwiftFormat not found (CLI or plugin)."; \
				echo "Install via 'brew install swiftformat' or add the SPM plugin dependency."; \
			fi; \
		else \
			echo "Swift toolchain not found. Skipping formatting."; \
		fi; \
	fi
