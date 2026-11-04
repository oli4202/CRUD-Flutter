# 📱 Flutter Contact Management App (Local Database CRUD)

A clean, modern, and user-friendly Contact Management application built with **Flutter** and a **Local SQLite Database** (`sqflite`).

---

## 🎯 Assignment Features & Requirements

### ✅ 1. Full CRUD Operations
- **Create (Add)**: Add a new contact with comprehensive validation.
- **Read (View)**: View all saved contacts displayed in sorted order with summary statistics.
- **Update (Edit)**: Edit any existing contact's details with pre-populated form fields.
- **Delete**: Remove a contact with a safety confirmation dialog and a floating **Undo** option.

### ✅ 2. Search by Name
- Real-time search bar that filters contacts as you type.
- Instant search query clearing button and friendly empty-search states.

### ✅ 3. Complete Contact Information
Each contact includes all required fields:
- 🆔 **ID**: Auto-incremented primary key
- 👤 **Name**: Full contact name (with live avatar initials preview)
- 📞 **Phone Number**: Formatted telephone/mobile number
- ✉️ **Email**: Validated email address
- 📍 **Address**: Street or home address

### 🌟 Bonus Feature: Favorite Contacts
- **1-Tap Favoriting**: Toggle favorites directly from the contact card or detail sheet.
- **Favorites Filter**: Filter and view only starred/favorite contacts with count indicators.

---

## 🎨 UI & Design Highlights

- **Material 3 Design System**: Styled with a contemporary Royal Blue (`#2563EB`) and Slate palette.
- **Dynamic Avatars**: Initials avatars automatically generated with unique pastel colors based on contact names.
- **Modal Bottom Sheets**: Streamlined sheets for adding, editing, and viewing full contact details with one-click clipboard copying.
- **Input Validation**: Form checks for non-empty names, valid phone numbers, and well-formed email addresses (`@` and domain).
- **Cross-Platform SQLite**: Uses native SQLite on mobile (`Android`/`iOS`) and `sqflite_common_ffi` on desktop (`Windows`/`macOS`/`Linux`), with a graceful fallback.

---

## 📁 Project Structure

```text
├── crud.dart             # Complete standalone application file
├── lib/
│   └── main.dart         # Flutter project entry point
├── pubspec.yaml          # Project dependencies (sqflite, path, sqflite_common_ffi)
└── README.md             # Documentation and submission guide
```

---

## 🚀 How to Run

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Run the App
To run on your connected device, emulator, or desktop:
```bash
flutter run
```
Or run the standalone file directly:
```bash
flutter run crud.dart
```

---

## 📤 Submission (GitHub)

To submit this project via GitHub:
```bash
git add .
git commit -m "Complete Flutter Local Database CRUD Contact App with Bonus"
git push origin <your-branch-name>
```
