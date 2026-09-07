import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

FirebaseFirestore getAppFirestore([FirebaseFirestore? customInstance]) {
  if (customInstance != null) return customInstance;
  try {
    if (Firebase.apps.isNotEmpty) {
      return FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'default',
      );
    }
  } catch (_) {}
  return FirebaseFirestore.instance;
}
