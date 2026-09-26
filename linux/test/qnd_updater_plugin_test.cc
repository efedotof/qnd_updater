#include <flutter_linux/flutter_linux.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include "include/qnd_updater/qnd_updater_plugin.h"
#include "qnd_updater_plugin_private.h"

namespace qnd_updater {
namespace test {

TEST(QndUpdaterPlugin, GetPlatformVersion) {
  g_autoptr(FlMethodResponse) response = get_platform_version();
  ASSERT_NE(response, nullptr);
  ASSERT_TRUE(FL_IS_METHOD_SUCCESS_RESPONSE(response));
  FlValue* result = fl_method_success_response_get_result(
      FL_METHOD_SUCCESS_RESPONSE(response));
  ASSERT_EQ(fl_value_get_type(result), FL_VALUE_TYPE_STRING);
  EXPECT_THAT(fl_value_get_string(result), testing::StartsWith("Linux "));
}

TEST(QndUpdaterPlugin, GetAppVersionReturnsString) {
  g_autoptr(FlMethodResponse) response = get_app_version();
  ASSERT_NE(response, nullptr);
  ASSERT_TRUE(FL_IS_METHOD_SUCCESS_RESPONSE(response));
  FlValue* result = fl_method_success_response_get_result(
      FL_METHOD_SUCCESS_RESPONSE(response));
  ASSERT_EQ(fl_value_get_type(result), FL_VALUE_TYPE_STRING);
}

}  // namespace test
}  // namespace qnd_updater