/* Desktop / test builds: no native share sheet. Share.share_text() falls
 * back to the clipboard when share() returns false. */
#include "ut_share_platform.h"

int ut_platform_available(void) {
	return 0;
}

int ut_platform_share(const char *text, const char *url) {
	(void)text;
	(void)url;
	return 0;
}

int ut_platform_thermal_state(void) {
	return -1;
}

int ut_platform_low_power(void) {
	return -1;
}

int ut_platform_receipt_kind(void) {
	return -1;
}
