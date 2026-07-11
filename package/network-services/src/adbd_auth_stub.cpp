#include <string>

#include "adb.h"
#include "adb_auth.h"
#include "transport.h"

bool auth_required = false;

void adbd_cloexec_auth_socket() {}
void adbd_auth_init(void) {}

bool adbd_auth_verify(const char*, size_t, const std::string&, std::string*) {
  return false;
}

void adbd_auth_verified(atransport* t) {
  handle_online(t);
  send_connect(t);
}

void send_auth_request(atransport* t) {
  adbd_auth_verified(t);
}

void adbd_auth_confirm_key(atransport* t) {
  adbd_auth_verified(t);
}

void adbd_notify_framework_connected_key(atransport*) {}
