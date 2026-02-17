// Main test file that imports all test suites
// Tests are organized into separate files by topic for better maintainability

import 'build_runner_test.dart' as build_runner_test;
import 'code_quality_test.dart' as code_quality_test;
import 'configuration_test.dart' as configuration_test;
import 'generation_styles_test.dart' as generation_styles_test;
import 'generator_test.dart' as generator_test;
import 'incremental_generation_test.dart' as incremental_generation_test;
import 'json_key_test.dart' as json_key_test;
import 'linting_test.dart' as linting_test;
import 'openapi_test.dart' as openapi_test;
import 'pluggable_styles_test.dart' as pluggable_styles_test;

void main() {
  generator_test.main();
  generation_styles_test.main();
  configuration_test.main();
  code_quality_test.main();
  json_key_test.main();
  linting_test.main();
  openapi_test.main();
  incremental_generation_test.main();
  pluggable_styles_test.main();
  build_runner_test.main();
}
