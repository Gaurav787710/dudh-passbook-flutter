# Firebase Email OTP Setup Guide / फायरबेस ईमेल OTP सेटअप गाइड

## 🔥 Firebase Trigger Email Extension सेटअप करें

Real OTP emails भेजने के लिए Firebase Console में "Trigger Email" extension इंस्टॉल करें।

---

## Step 1: Firebase Console में जाएं

1. Open: https://console.firebase.google.com
2. अपना project select करें: `my-diray-83de8`

---

## Step 2: Enable Anonymous Authentication (जरूरी!)

1. Firebase Console > Authentication > Sign-in method
2. "Anonymous" पर क्लिक करें
3. **Enable** करें और Save करें

---

## Step 3: Firestore Rules अपडेट करें (जरूरी!)

Firebase Console > Firestore Database > Rules में ये rules add करें:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Allow ANY authenticated user (including anonymous) to read/write email_otps
    match /email_otps/{email} {
      allow read, write: if request.auth != null;
    }
    
    // Allow ANY authenticated user to write to mail collection (for Trigger Email)
    match /mail/{document=**} {
      allow create: if request.auth != null;
      allow read: if false;
    }
    
    // Users collection - only owner can read/write
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Dairies collection - any authenticated user
    match /dairies/{dairyId} {
      allow read, write: if request.auth != null;
    }
    
    // Farmers collection under dairies
    match /dairies/{dairyId}/farmers/{farmerId} {
      allow read, write: if request.auth != null;
    }
    
    // Milk entries under farmers
    match /dairies/{dairyId}/farmers/{farmerId}/milkEntries/{entryId} {
      allow read, write: if request.auth != null;
    }
    
    // Payments under farmers
    match /dairies/{dairyId}/farmers/{farmerId}/payments/{paymentId} {
      allow read, write: if request.auth != null;
    }
  }
}
```

**Publish** पर क्लिक करें!

---

## Step 3: Trigger Email Extension इंस्टॉल करें

1. Firebase Console > Extensions पर जाएं
2. "Explore Extensions" पर क्लिक करें
3. Search करें: **"Trigger Email"** by Firebase
4. **Install** पर क्लिक करें

### Extension Configuration:

| Setting | Value |
|---------|-------|
| **SMTP connection URI** | `smtps://your-email@gmail.com:app-password@smtp.gmail.com:465` |
| **Email documents collection** | `mail` |
| **Default FROM address** | `Dudh Passbook <your-email@gmail.com>` |
| **Default Reply-To address** | `your-email@gmail.com` |

---

## Step 4: Gmail App Password बनाएं (Gmail SMTP के लिए)

### Gmail App Password Setup:

1. Go to: https://myaccount.google.com/security
2. Enable **2-Step Verification** (अगर enabled नहीं है)
3. Go to: https://myaccount.google.com/apppasswords
4. Create App Password:
   - Select app: **Mail**
   - Select device: **Other** → "Dudh Passbook"
5. **16-character password** copy करें

### SMTP URI Format:
```
smtps://your-email@gmail.com:xxxx-xxxx-xxxx-xxxx@smtp.gmail.com:465
```

Replace:
- `your-email@gmail.com` → आपका Gmail
- `xxxx-xxxx-xxxx-xxxx` → 16-character App Password (spaces हटाएं)

---

## Step 5: Test करें

1. App में Sign Up पर जाएं
2. Email enter करें
3. "Create Account" पर क्लिक करें
4. "Send OTP" पर क्लिक करें
5. ✅ Email आना चाहिए OTP के साथ!

---

## Alternative: Other Email Services

### SendGrid:
```
smtps://apikey:SG.your-sendgrid-api-key@smtp.sendgrid.net:465
```

### Mailgun:
```
smtps://postmaster@your-domain.mailgun.org:your-password@smtp.mailgun.org:465
```

---

## 🚨 Troubleshooting

### Issue: "Permission Denied" Error
- Check Firestore Rules (Step 2)
- Make sure anonymous auth is enabled

### Issue: Email Not Received
- Check spam folder
- Verify SMTP settings in Extension
- Check Firebase Console > Extensions > Trigger Email > Logs

### Issue: App Password Not Working
- Make sure 2-Step Verification is enabled
- Create a new App Password
- Remove spaces from password in SMTP URI

---

## ✅ Current Setup Status

| Feature | Status |
|---------|--------|
| Anonymous Auth | ✅ Enabled |
| OTP Generation | ✅ Working (local + Firestore) |
| OTP Verification | ✅ Working |
| Email Sending | ⏳ Needs Extension Setup |

---

## 📞 Support

If you face any issues, check Firebase Console logs or contact support.

---

**Note:** Real email भेजने के लिए Trigger Email Extension setup करना जरूरी है। बिना extension के, test OTP screen पर दिखेगा।
