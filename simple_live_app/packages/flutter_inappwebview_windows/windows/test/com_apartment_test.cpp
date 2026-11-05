#include <windows.h>
#include <cassert>
#include <thread>
#include "../utils/com_apartment.h"

using flutter_inappwebview_plugin::ComApartment;
HRESULT apartmentStatus() {
  APTTYPE type;
  APTTYPEQUALIFIER qualifier;
  return CoGetApartmentType(&type, &qualifier);
}
int main() {
  std::thread fresh([] {
    assert(apartmentStatus() == CO_E_NOTINITIALIZED);
    {
      ComApartment owner;
      assert(SUCCEEDED(owner.result()));
      { ComApartment nested; assert(nested.result() == S_FALSE); }
      assert(SUCCEEDED(apartmentStatus()));
    }
    assert(apartmentStatus() == CO_E_NOTINITIALIZED);
  });
  fresh.join();
  std::thread mta([] {
    assert(SUCCEEDED(CoInitializeEx(nullptr, COINIT_MULTITHREADED)));
    { ComApartment wrongMode; assert(wrongMode.result() == RPC_E_CHANGED_MODE); }
    assert(SUCCEEDED(apartmentStatus()));
    CoUninitialize();
    assert(apartmentStatus() == CO_E_NOTINITIALIZED);
  });
  mta.join();
  std::thread platform([] {
    assert(apartmentStatus() == CO_E_NOTINITIALIZED);
    // Hundreds of environment wrapper lifetimes must neither uninitialize the
    // platform STA nor add a COM reference on every create/retry.
    for (int i = 0; i < 100; ++i) {
      assert(SUCCEEDED(flutter_inappwebview_plugin::ensureWebViewComApartment()));
      { ComApartment environment; assert(environment.result() == S_FALSE); }
      assert(SUCCEEDED(apartmentStatus()));
    }
  });
  platform.join();
}
