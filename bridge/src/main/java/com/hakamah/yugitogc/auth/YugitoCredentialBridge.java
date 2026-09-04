package com.hakamah.yugitogc.auth;

import android.app.Activity;
import android.os.CancellationSignal;
import android.util.Log;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;

import androidx.credentials.Credential;
import androidx.credentials.CredentialManager;
import androidx.credentials.CredentialManagerCallback;
import androidx.credentials.CustomCredential;
import androidx.credentials.GetCredentialRequest;
import androidx.credentials.GetCredentialResponse;
import androidx.credentials.exceptions.GetCredentialCancellationException;
import androidx.credentials.exceptions.GetCredentialException;
import androidx.credentials.exceptions.GetCredentialInterruptedException;
import androidx.credentials.exceptions.GetCredentialProviderConfigurationException;
import androidx.credentials.exceptions.GetCredentialUnsupportedException;
import androidx.credentials.exceptions.NoCredentialException;

import com.google.android.libraries.identity.googleid.GetGoogleIdOption;
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption;
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential;

import java.security.MessageDigest;
import java.util.Locale;
import java.util.concurrent.Executor;

/**
 * YUGITO GC native Android Credential Manager bridge.
 *
 * Security rules:
 * - never log ID token, e-mail, display name or profile identity;
 * - bind the Google ID token to the server-issued device_code via nonce;
 * - keep the token in memory only until Godot calls takeIdToken().
 */
public final class YugitoCredentialBridge {
    private static final String TAG = "YugitoCM";

    public static final int STATE_IDLE = 0;
    public static final int STATE_RUNNING = 1;
    public static final int STATE_SUCCESS = 2;
    public static final int STATE_CANCELLED = 3;
    public static final int STATE_ERROR = 4;

    private static final Object LOCK = new Object();
    private static volatile int state = STATE_IDLE;
    private static volatile String stage = "idle";
    private static volatile String flow = "none";
    private static volatile String errorCode = "";
    private static volatile String errorMessage = "";
    private static volatile String idToken = "";
    private static volatile CancellationSignal cancellationSignal = null;
    private static volatile boolean explicitFallbackAttempted = false;

    private YugitoCredentialBridge() {}

    public static String getBridgeVersion() {
        return "YUGITO-CM-BRIDGE-1.0|credentials-1.6.0|googleid-1.2.0";
    }

    public static String getPackageName(Activity activity) {
        return activity == null ? "" : activity.getPackageName();
    }

    @SuppressWarnings("deprecation")
    public static String getSigningSha1(Activity activity) {
        if (activity == null) return "";
        try {
            PackageManager pm = activity.getPackageManager();
            Signature signature = null;
            if (android.os.Build.VERSION.SDK_INT >= 28) {
                PackageInfo info = pm.getPackageInfo(activity.getPackageName(), PackageManager.GET_SIGNING_CERTIFICATES);
                if (info.signingInfo != null) {
                    Signature[] signatures = info.signingInfo.hasMultipleSigners()
                            ? info.signingInfo.getApkContentsSigners()
                            : info.signingInfo.getSigningCertificateHistory();
                    if (signatures != null && signatures.length > 0) signature = signatures[0];
                }
            } else {
                PackageInfo info = pm.getPackageInfo(activity.getPackageName(), PackageManager.GET_SIGNATURES);
                if (info.signatures != null && info.signatures.length > 0) signature = info.signatures[0];
            }
            if (signature == null) return "";
            byte[] digest = MessageDigest.getInstance("SHA-1").digest(signature.toByteArray());
            StringBuilder out = new StringBuilder();
            for (int i = 0; i < digest.length; i++) {
                if (i > 0) out.append(':');
                out.append(String.format(Locale.US, "%02X", digest[i] & 0xff));
            }
            return out.toString();
        } catch (Throwable t) {
            return "ERROR:" + t.getClass().getSimpleName();
        }
    }

    public static int getState() { return state; }
    public static String getStage() { return stage; }
    public static String getFlow() { return flow; }
    public static String getErrorCode() { return errorCode; }
    public static String getErrorMessage() { return errorMessage; }

    public static String takeIdToken() {
        synchronized (LOCK) {
            String token = idToken == null ? "" : idToken;
            idToken = "";
            return token;
        }
    }

    public static void cancel() {
        CancellationSignal signal = cancellationSignal;
        if (signal != null) {
            try { signal.cancel(); } catch (Throwable ignored) {}
        }
        synchronized (LOCK) {
            if (state == STATE_RUNNING) {
                state = STATE_CANCELLED;
                stage = "cancelled_by_app";
                errorCode = "cancelled_by_app";
                errorMessage = "";
            }
            cancellationSignal = null;
            idToken = "";
        }
    }

    public static void reset() {
        CancellationSignal signal = cancellationSignal;
        if (signal != null) {
            try { signal.cancel(); } catch (Throwable ignored) {}
        }
        synchronized (LOCK) {
            state = STATE_IDLE;
            stage = "idle";
            flow = "none";
            errorCode = "";
            errorMessage = "";
            idToken = "";
            cancellationSignal = null;
            explicitFallbackAttempted = false;
        }
    }

    public static boolean start(Activity activity, String serverClientId, String nonce) {
        if (activity == null) {
            fail("activity_null", "Android Activity unavailable");
            return false;
        }
        if (serverClientId == null || serverClientId.trim().isEmpty()) {
            fail("client_id_missing", "Server client ID missing");
            return false;
        }
        if (nonce == null || nonce.trim().isEmpty()) {
            fail("nonce_missing", "Nonce missing");
            return false;
        }

        synchronized (LOCK) {
            if (state == STATE_RUNNING) return false;
            state = STATE_RUNNING;
            stage = "accepted";
            flow = "google_id_option";
            errorCode = "";
            errorMessage = "";
            idToken = "";
            explicitFallbackAttempted = false;
        }

        try {
            activity.runOnUiThread(() -> requestGoogleIdOption(activity, serverClientId, nonce));
            return true;
        } catch (Throwable t) {
            failThrowable("ui_dispatch_failed", t);
            return false;
        }
    }

    private static void requestGoogleIdOption(Activity activity, String serverClientId, String nonce) {
        try {
            stage = "credential_manager_create";
            flow = "google_id_option";
            CredentialManager manager = CredentialManager.create(activity);

            stage = "build_google_id_option";
            GetGoogleIdOption option = new GetGoogleIdOption.Builder()
                    .setFilterByAuthorizedAccounts(false)
                    .setAutoSelectEnabled(false)
                    .setServerClientId(serverClientId)
                    .setNonce(nonce)
                    .build();

            GetCredentialRequest request = new GetCredentialRequest.Builder()
                    .addCredentialOption(option)
                    .build();

            stage = "native_sheet_requested";
            runRequest(activity, manager, request, serverClientId, nonce, false);
        } catch (Throwable t) {
            failThrowable("google_id_request_build_failed", t);
        }
    }

    private static void requestExplicitGoogle(Activity activity, CredentialManager manager,
                                              String serverClientId, String nonce) {
        try {
            explicitFallbackAttempted = true;
            flow = "sign_in_with_google_option";
            stage = "build_explicit_google_option";

            GetSignInWithGoogleOption option = new GetSignInWithGoogleOption.Builder(serverClientId)
                    .setNonce(nonce)
                    .build();

            GetCredentialRequest request = new GetCredentialRequest.Builder()
                    .addCredentialOption(option)
                    .build();

            stage = "native_explicit_google_requested";
            runRequest(activity, manager, request, serverClientId, nonce, true);
        } catch (Throwable t) {
            failThrowable("explicit_google_request_build_failed", t);
        }
    }

    private static void runRequest(Activity activity, CredentialManager manager,
                                   GetCredentialRequest request, String serverClientId,
                                   String nonce, boolean explicitFlow) {
        final CancellationSignal signal = new CancellationSignal();
        cancellationSignal = signal;
        final Executor mainExecutor = command -> activity.runOnUiThread(command);

        manager.getCredentialAsync(
                activity,
                request,
                signal,
                mainExecutor,
                new CredentialManagerCallback<GetCredentialResponse, GetCredentialException>() {
                    @Override
                    public void onResult(GetCredentialResponse result) {
                        cancellationSignal = null;
                        handleCredentialResult(result);
                    }

                    @Override
                    public void onError(GetCredentialException e) {
                        cancellationSignal = null;
                        if (!explicitFlow && e instanceof NoCredentialException && !explicitFallbackAttempted) {
                            stage = "no_credential_fallback_to_explicit_google";
                            requestExplicitGoogle(activity, manager, serverClientId, nonce);
                            return;
                        }
                        handleCredentialError(e);
                    }
                }
        );
    }

    private static void handleCredentialResult(GetCredentialResponse result) {
        try {
            stage = "credential_returned";
            if (result == null) {
                fail("empty_response", "Credential response was null");
                return;
            }
            Credential credential = result.getCredential();
            if (!(credential instanceof CustomCredential)) {
                fail("unexpected_credential_class", credential == null ? "null" : credential.getClass().getName());
                return;
            }

            CustomCredential custom = (CustomCredential) credential;
            if (!GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL.equals(custom.getType())) {
                fail("unexpected_credential_type", custom.getType());
                return;
            }

            stage = "parse_google_id_token_credential";
            GoogleIdTokenCredential googleCredential = GoogleIdTokenCredential.createFrom(custom.getData());
            String token = googleCredential.getIdToken();
            if (token == null || token.isEmpty()) {
                fail("empty_id_token", "Google credential returned an empty ID token");
                return;
            }

            synchronized (LOCK) {
                idToken = token;
                state = STATE_SUCCESS;
                stage = "success_token_ready";
                errorCode = "";
                errorMessage = "";
            }
            Log.i(TAG, "Credential Manager success: Google ID token stored in memory (content not logged)");
        } catch (Throwable t) {
            failThrowable("credential_parse_failed", t);
        }
    }

    private static void handleCredentialError(GetCredentialException e) {
        if (e instanceof GetCredentialCancellationException) {
            synchronized (LOCK) {
                state = STATE_CANCELLED;
                stage = "user_cancelled";
                errorCode = "user_cancelled";
                errorMessage = "";
                idToken = "";
            }
            return;
        }

        String code;
        if (e instanceof NoCredentialException) code = "no_credential";
        else if (e instanceof GetCredentialProviderConfigurationException) code = "provider_configuration";
        else if (e instanceof GetCredentialUnsupportedException) code = "unsupported";
        else if (e instanceof GetCredentialInterruptedException) code = "interrupted";
        else code = "credential_error";
        failThrowable(code, e);
    }

    private static void failThrowable(String code, Throwable t) {
        String simple = t == null ? "Throwable" : t.getClass().getSimpleName();
        String message = t == null || t.getMessage() == null ? "" : t.getMessage();
        if (message.length() > 300) message = message.substring(0, 300);
        fail(code, simple + (message.isEmpty() ? "" : ": " + message));
    }

    private static void fail(String code, String message) {
        synchronized (LOCK) {
            state = STATE_ERROR;
            stage = "error";
            errorCode = code == null ? "error" : code;
            errorMessage = message == null ? "" : message;
            idToken = "";
            cancellationSignal = null;
        }
        Log.w(TAG, "Credential Manager error code=" + errorCode + " (no identity/token logged)");
    }
}
