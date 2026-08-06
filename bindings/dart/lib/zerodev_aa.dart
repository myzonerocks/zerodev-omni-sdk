/// Dart and Flutter binding for the ZeroDev Omni SDK.
///
/// ERC-4337 smart accounts on a Zig core, over C FFI: Kernel accounts, gasless
/// UserOperations, custom signers, and EIP-7702 delegation.
///
/// ```dart
/// import 'package:zerodev_aa/zerodev_aa.dart';
///
/// final ctx = Context.create(projectId, chainId: 11155111);
/// final signer = Signer.generate();
/// final account = ctx.newAccount(signer);
/// final hash = account.sendUserOp([Call(target: account.getAddress())]);
/// final receipt = account.waitForUserOperationReceipt(hash);
/// account.dispose();
/// signer.dispose();
/// ctx.dispose();
/// ```
library;

export 'src/error.dart' show AaErrorCode, AaException, lastErrorMessage;
export 'src/hex.dart' show hexDecode, hexEncode;
export 'src/native_loader.dart' show NativeLibrary;
export 'src/sdk.dart'
    show
        Account,
        AccountAsync,
        Context,
        HttpClientTransport,
        HttpTransport,
        HttpTransportException,
        Signer,
        SignerImpl,
        UserOp;
export 'src/types.dart'
    show
        Address,
        Authorization,
        Call,
        GasMiddleware,
        Hash,
        KernelVersion,
        PaymasterMiddleware,
        UserOperationReceipt;
