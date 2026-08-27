import 'package:flutter/foundation.dart';

class LojaNav {
  LojaNav._();
  static final ValueNotifier<bool> open = ValueNotifier<bool>(false);
  static final ValueNotifier<int> goToTab = ValueNotifier<int>(-1);

  static void abrirLoja() => open.value = true;
  static void fecharLoja() => open.value = false;
  static void irParaSala() {
    open.value = false;
    goToTab.value = 1; // aba SALA
  }
}
