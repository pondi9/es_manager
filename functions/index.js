const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {setGlobalOptions} = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();

// Ustawienie lokalizacji na Europę
setGlobalOptions({region: "europe-west3"});

// Skrypt wysyłający PUSH, gdy w bazie pojawi się nowe zlecenie 'push_requests'
exports.sendPushNotification = onDocumentCreated("push_requests/{requestId}", async (event) => {
    const request = event.data.data();
    if (!request) return;

    const message = {
        notification: {
            title: request.title,
            body: request.body,
        },
        android: {
            priority: "high",
            notification: {
                sound: "default",
                clickAction: "FLUTTER_NOTIFICATION_CLICK",
                channelId: "high_importance_channel"
            }
        },
        token: request.to
    };

    try {
        await admin.messaging().send(message);
        console.log("Powiadomienie wysłane do:", request.to);
        return event.data.ref.update({
            status: "sent",
            sentAt: admin.firestore.FieldValue.serverTimestamp()
        });
    } catch (error) {
        console.error("Błąd wysyłki PUSH:", error);
        return event.data.ref.update({
            status: "error",
            error: error.toString()
        });
    }
});
