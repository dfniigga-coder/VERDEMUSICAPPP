import 'package:flutter/material.dart';

/// Диалог с полем ввода. Возвращает trimmed строку или null (отмена).Future<String?> showTextDialog(
  BuildContext context, {
  required String title,
  String? initial,
  String hintText = 'Название',
  String positiveLabel = 'Сохранить',
}) async {
  final controller = TextEditingController(text: initial);
  String? result;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hintText),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: Text(positiveLabel),
          ),
        ],
      );
    },
  );

  final raw = controller.text.trim();
  if (raw.isNotEmpty) result = raw;
  controller.dispose();
  return result;
}

/// Диалог подтверждения. true — «Да».
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Удалить',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB3261E),
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Небольшая обёртка для цвета удаления.
class AppColors {
  AppColors._();
  static const Color deleteRed = Color(0xFFB3261E);
}
