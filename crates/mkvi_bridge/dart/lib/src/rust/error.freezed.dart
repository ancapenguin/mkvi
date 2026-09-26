// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CoreFailure {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreFailure);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'CoreFailure()';
}


}

/// @nodoc
class $CoreFailureCopyWith<$Res>  {
$CoreFailureCopyWith(CoreFailure _, $Res Function(CoreFailure) __);
}


/// Adds pattern-matching-related methods to [CoreFailure].
extension CoreFailurePatterns on CoreFailure {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CoreFailure_HistoryLocked value)?  historyLocked,TResult Function( CoreFailure_PeerStoreLocked value)?  peerStoreLocked,TResult Function( CoreFailure_FileSinkLocked value)?  fileSinkLocked,TResult Function( CoreFailure_NoOpenTransfer value)?  noOpenTransfer,TResult Function( CoreFailure_TooManyTransfers value)?  tooManyTransfers,TResult Function( CoreFailure_DuplicateTransfer value)?  duplicateTransfer,TResult Function( CoreFailure_TransferTooLarge value)?  transferTooLarge,TResult Function( CoreFailure_Security value)?  security,TResult Function( CoreFailure_Io value)?  io,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CoreFailure_HistoryLocked() when historyLocked != null:
return historyLocked(_that);case CoreFailure_PeerStoreLocked() when peerStoreLocked != null:
return peerStoreLocked(_that);case CoreFailure_FileSinkLocked() when fileSinkLocked != null:
return fileSinkLocked(_that);case CoreFailure_NoOpenTransfer() when noOpenTransfer != null:
return noOpenTransfer(_that);case CoreFailure_TooManyTransfers() when tooManyTransfers != null:
return tooManyTransfers(_that);case CoreFailure_DuplicateTransfer() when duplicateTransfer != null:
return duplicateTransfer(_that);case CoreFailure_TransferTooLarge() when transferTooLarge != null:
return transferTooLarge(_that);case CoreFailure_Security() when security != null:
return security(_that);case CoreFailure_Io() when io != null:
return io(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CoreFailure_HistoryLocked value)  historyLocked,required TResult Function( CoreFailure_PeerStoreLocked value)  peerStoreLocked,required TResult Function( CoreFailure_FileSinkLocked value)  fileSinkLocked,required TResult Function( CoreFailure_NoOpenTransfer value)  noOpenTransfer,required TResult Function( CoreFailure_TooManyTransfers value)  tooManyTransfers,required TResult Function( CoreFailure_DuplicateTransfer value)  duplicateTransfer,required TResult Function( CoreFailure_TransferTooLarge value)  transferTooLarge,required TResult Function( CoreFailure_Security value)  security,required TResult Function( CoreFailure_Io value)  io,}){
final _that = this;
switch (_that) {
case CoreFailure_HistoryLocked():
return historyLocked(_that);case CoreFailure_PeerStoreLocked():
return peerStoreLocked(_that);case CoreFailure_FileSinkLocked():
return fileSinkLocked(_that);case CoreFailure_NoOpenTransfer():
return noOpenTransfer(_that);case CoreFailure_TooManyTransfers():
return tooManyTransfers(_that);case CoreFailure_DuplicateTransfer():
return duplicateTransfer(_that);case CoreFailure_TransferTooLarge():
return transferTooLarge(_that);case CoreFailure_Security():
return security(_that);case CoreFailure_Io():
return io(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CoreFailure_HistoryLocked value)?  historyLocked,TResult? Function( CoreFailure_PeerStoreLocked value)?  peerStoreLocked,TResult? Function( CoreFailure_FileSinkLocked value)?  fileSinkLocked,TResult? Function( CoreFailure_NoOpenTransfer value)?  noOpenTransfer,TResult? Function( CoreFailure_TooManyTransfers value)?  tooManyTransfers,TResult? Function( CoreFailure_DuplicateTransfer value)?  duplicateTransfer,TResult? Function( CoreFailure_TransferTooLarge value)?  transferTooLarge,TResult? Function( CoreFailure_Security value)?  security,TResult? Function( CoreFailure_Io value)?  io,}){
final _that = this;
switch (_that) {
case CoreFailure_HistoryLocked() when historyLocked != null:
return historyLocked(_that);case CoreFailure_PeerStoreLocked() when peerStoreLocked != null:
return peerStoreLocked(_that);case CoreFailure_FileSinkLocked() when fileSinkLocked != null:
return fileSinkLocked(_that);case CoreFailure_NoOpenTransfer() when noOpenTransfer != null:
return noOpenTransfer(_that);case CoreFailure_TooManyTransfers() when tooManyTransfers != null:
return tooManyTransfers(_that);case CoreFailure_DuplicateTransfer() when duplicateTransfer != null:
return duplicateTransfer(_that);case CoreFailure_TransferTooLarge() when transferTooLarge != null:
return transferTooLarge(_that);case CoreFailure_Security() when security != null:
return security(_that);case CoreFailure_Io() when io != null:
return io(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String message)?  historyLocked,TResult Function( String message)?  peerStoreLocked,TResult Function( String message)?  fileSinkLocked,TResult Function( String message)?  noOpenTransfer,TResult Function( String message)?  tooManyTransfers,TResult Function( String message)?  duplicateTransfer,TResult Function( String message)?  transferTooLarge,TResult Function( SecurityFailure failure)?  security,TResult Function( String message)?  io,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CoreFailure_HistoryLocked() when historyLocked != null:
return historyLocked(_that.message);case CoreFailure_PeerStoreLocked() when peerStoreLocked != null:
return peerStoreLocked(_that.message);case CoreFailure_FileSinkLocked() when fileSinkLocked != null:
return fileSinkLocked(_that.message);case CoreFailure_NoOpenTransfer() when noOpenTransfer != null:
return noOpenTransfer(_that.message);case CoreFailure_TooManyTransfers() when tooManyTransfers != null:
return tooManyTransfers(_that.message);case CoreFailure_DuplicateTransfer() when duplicateTransfer != null:
return duplicateTransfer(_that.message);case CoreFailure_TransferTooLarge() when transferTooLarge != null:
return transferTooLarge(_that.message);case CoreFailure_Security() when security != null:
return security(_that.failure);case CoreFailure_Io() when io != null:
return io(_that.message);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String message)  historyLocked,required TResult Function( String message)  peerStoreLocked,required TResult Function( String message)  fileSinkLocked,required TResult Function( String message)  noOpenTransfer,required TResult Function( String message)  tooManyTransfers,required TResult Function( String message)  duplicateTransfer,required TResult Function( String message)  transferTooLarge,required TResult Function( SecurityFailure failure)  security,required TResult Function( String message)  io,}) {final _that = this;
switch (_that) {
case CoreFailure_HistoryLocked():
return historyLocked(_that.message);case CoreFailure_PeerStoreLocked():
return peerStoreLocked(_that.message);case CoreFailure_FileSinkLocked():
return fileSinkLocked(_that.message);case CoreFailure_NoOpenTransfer():
return noOpenTransfer(_that.message);case CoreFailure_TooManyTransfers():
return tooManyTransfers(_that.message);case CoreFailure_DuplicateTransfer():
return duplicateTransfer(_that.message);case CoreFailure_TransferTooLarge():
return transferTooLarge(_that.message);case CoreFailure_Security():
return security(_that.failure);case CoreFailure_Io():
return io(_that.message);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String message)?  historyLocked,TResult? Function( String message)?  peerStoreLocked,TResult? Function( String message)?  fileSinkLocked,TResult? Function( String message)?  noOpenTransfer,TResult? Function( String message)?  tooManyTransfers,TResult? Function( String message)?  duplicateTransfer,TResult? Function( String message)?  transferTooLarge,TResult? Function( SecurityFailure failure)?  security,TResult? Function( String message)?  io,}) {final _that = this;
switch (_that) {
case CoreFailure_HistoryLocked() when historyLocked != null:
return historyLocked(_that.message);case CoreFailure_PeerStoreLocked() when peerStoreLocked != null:
return peerStoreLocked(_that.message);case CoreFailure_FileSinkLocked() when fileSinkLocked != null:
return fileSinkLocked(_that.message);case CoreFailure_NoOpenTransfer() when noOpenTransfer != null:
return noOpenTransfer(_that.message);case CoreFailure_TooManyTransfers() when tooManyTransfers != null:
return tooManyTransfers(_that.message);case CoreFailure_DuplicateTransfer() when duplicateTransfer != null:
return duplicateTransfer(_that.message);case CoreFailure_TransferTooLarge() when transferTooLarge != null:
return transferTooLarge(_that.message);case CoreFailure_Security() when security != null:
return security(_that.failure);case CoreFailure_Io() when io != null:
return io(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class CoreFailure_HistoryLocked extends CoreFailure {
  const CoreFailure_HistoryLocked({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreFailure_HistoryLockedCopyWith<CoreFailure_HistoryLocked> get copyWith => _$CoreFailure_HistoryLockedCopyWithImpl<CoreFailure_HistoryLocked>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreFailure_HistoryLocked&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'CoreFailure.historyLocked(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreFailure_HistoryLockedCopyWith<$Res> implements $CoreFailureCopyWith<$Res> {
  factory $CoreFailure_HistoryLockedCopyWith(CoreFailure_HistoryLocked value, $Res Function(CoreFailure_HistoryLocked) _then) = _$CoreFailure_HistoryLockedCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreFailure_HistoryLockedCopyWithImpl<$Res>
    implements $CoreFailure_HistoryLockedCopyWith<$Res> {
  _$CoreFailure_HistoryLockedCopyWithImpl(this._self, this._then);

  final CoreFailure_HistoryLocked _self;
  final $Res Function(CoreFailure_HistoryLocked) _then;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreFailure_HistoryLocked(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreFailure_PeerStoreLocked extends CoreFailure {
  const CoreFailure_PeerStoreLocked({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreFailure_PeerStoreLockedCopyWith<CoreFailure_PeerStoreLocked> get copyWith => _$CoreFailure_PeerStoreLockedCopyWithImpl<CoreFailure_PeerStoreLocked>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreFailure_PeerStoreLocked&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'CoreFailure.peerStoreLocked(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreFailure_PeerStoreLockedCopyWith<$Res> implements $CoreFailureCopyWith<$Res> {
  factory $CoreFailure_PeerStoreLockedCopyWith(CoreFailure_PeerStoreLocked value, $Res Function(CoreFailure_PeerStoreLocked) _then) = _$CoreFailure_PeerStoreLockedCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreFailure_PeerStoreLockedCopyWithImpl<$Res>
    implements $CoreFailure_PeerStoreLockedCopyWith<$Res> {
  _$CoreFailure_PeerStoreLockedCopyWithImpl(this._self, this._then);

  final CoreFailure_PeerStoreLocked _self;
  final $Res Function(CoreFailure_PeerStoreLocked) _then;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreFailure_PeerStoreLocked(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreFailure_FileSinkLocked extends CoreFailure {
  const CoreFailure_FileSinkLocked({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreFailure_FileSinkLockedCopyWith<CoreFailure_FileSinkLocked> get copyWith => _$CoreFailure_FileSinkLockedCopyWithImpl<CoreFailure_FileSinkLocked>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreFailure_FileSinkLocked&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'CoreFailure.fileSinkLocked(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreFailure_FileSinkLockedCopyWith<$Res> implements $CoreFailureCopyWith<$Res> {
  factory $CoreFailure_FileSinkLockedCopyWith(CoreFailure_FileSinkLocked value, $Res Function(CoreFailure_FileSinkLocked) _then) = _$CoreFailure_FileSinkLockedCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreFailure_FileSinkLockedCopyWithImpl<$Res>
    implements $CoreFailure_FileSinkLockedCopyWith<$Res> {
  _$CoreFailure_FileSinkLockedCopyWithImpl(this._self, this._then);

  final CoreFailure_FileSinkLocked _self;
  final $Res Function(CoreFailure_FileSinkLocked) _then;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreFailure_FileSinkLocked(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreFailure_NoOpenTransfer extends CoreFailure {
  const CoreFailure_NoOpenTransfer({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreFailure_NoOpenTransferCopyWith<CoreFailure_NoOpenTransfer> get copyWith => _$CoreFailure_NoOpenTransferCopyWithImpl<CoreFailure_NoOpenTransfer>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreFailure_NoOpenTransfer&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'CoreFailure.noOpenTransfer(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreFailure_NoOpenTransferCopyWith<$Res> implements $CoreFailureCopyWith<$Res> {
  factory $CoreFailure_NoOpenTransferCopyWith(CoreFailure_NoOpenTransfer value, $Res Function(CoreFailure_NoOpenTransfer) _then) = _$CoreFailure_NoOpenTransferCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreFailure_NoOpenTransferCopyWithImpl<$Res>
    implements $CoreFailure_NoOpenTransferCopyWith<$Res> {
  _$CoreFailure_NoOpenTransferCopyWithImpl(this._self, this._then);

  final CoreFailure_NoOpenTransfer _self;
  final $Res Function(CoreFailure_NoOpenTransfer) _then;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreFailure_NoOpenTransfer(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreFailure_TooManyTransfers extends CoreFailure {
  const CoreFailure_TooManyTransfers({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreFailure_TooManyTransfersCopyWith<CoreFailure_TooManyTransfers> get copyWith => _$CoreFailure_TooManyTransfersCopyWithImpl<CoreFailure_TooManyTransfers>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreFailure_TooManyTransfers&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'CoreFailure.tooManyTransfers(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreFailure_TooManyTransfersCopyWith<$Res> implements $CoreFailureCopyWith<$Res> {
  factory $CoreFailure_TooManyTransfersCopyWith(CoreFailure_TooManyTransfers value, $Res Function(CoreFailure_TooManyTransfers) _then) = _$CoreFailure_TooManyTransfersCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreFailure_TooManyTransfersCopyWithImpl<$Res>
    implements $CoreFailure_TooManyTransfersCopyWith<$Res> {
  _$CoreFailure_TooManyTransfersCopyWithImpl(this._self, this._then);

  final CoreFailure_TooManyTransfers _self;
  final $Res Function(CoreFailure_TooManyTransfers) _then;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreFailure_TooManyTransfers(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreFailure_DuplicateTransfer extends CoreFailure {
  const CoreFailure_DuplicateTransfer({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreFailure_DuplicateTransferCopyWith<CoreFailure_DuplicateTransfer> get copyWith => _$CoreFailure_DuplicateTransferCopyWithImpl<CoreFailure_DuplicateTransfer>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreFailure_DuplicateTransfer&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'CoreFailure.duplicateTransfer(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreFailure_DuplicateTransferCopyWith<$Res> implements $CoreFailureCopyWith<$Res> {
  factory $CoreFailure_DuplicateTransferCopyWith(CoreFailure_DuplicateTransfer value, $Res Function(CoreFailure_DuplicateTransfer) _then) = _$CoreFailure_DuplicateTransferCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreFailure_DuplicateTransferCopyWithImpl<$Res>
    implements $CoreFailure_DuplicateTransferCopyWith<$Res> {
  _$CoreFailure_DuplicateTransferCopyWithImpl(this._self, this._then);

  final CoreFailure_DuplicateTransfer _self;
  final $Res Function(CoreFailure_DuplicateTransfer) _then;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreFailure_DuplicateTransfer(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreFailure_TransferTooLarge extends CoreFailure {
  const CoreFailure_TransferTooLarge({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreFailure_TransferTooLargeCopyWith<CoreFailure_TransferTooLarge> get copyWith => _$CoreFailure_TransferTooLargeCopyWithImpl<CoreFailure_TransferTooLarge>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreFailure_TransferTooLarge&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'CoreFailure.transferTooLarge(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreFailure_TransferTooLargeCopyWith<$Res> implements $CoreFailureCopyWith<$Res> {
  factory $CoreFailure_TransferTooLargeCopyWith(CoreFailure_TransferTooLarge value, $Res Function(CoreFailure_TransferTooLarge) _then) = _$CoreFailure_TransferTooLargeCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreFailure_TransferTooLargeCopyWithImpl<$Res>
    implements $CoreFailure_TransferTooLargeCopyWith<$Res> {
  _$CoreFailure_TransferTooLargeCopyWithImpl(this._self, this._then);

  final CoreFailure_TransferTooLarge _self;
  final $Res Function(CoreFailure_TransferTooLarge) _then;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreFailure_TransferTooLarge(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreFailure_Security extends CoreFailure {
  const CoreFailure_Security({required this.failure}): super._();
  

 final  SecurityFailure failure;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreFailure_SecurityCopyWith<CoreFailure_Security> get copyWith => _$CoreFailure_SecurityCopyWithImpl<CoreFailure_Security>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreFailure_Security&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode => Object.hash(runtimeType,failure);

@override
String toString() {
  return 'CoreFailure.security(failure: $failure)';
}


}

/// @nodoc
abstract mixin class $CoreFailure_SecurityCopyWith<$Res> implements $CoreFailureCopyWith<$Res> {
  factory $CoreFailure_SecurityCopyWith(CoreFailure_Security value, $Res Function(CoreFailure_Security) _then) = _$CoreFailure_SecurityCopyWithImpl;
@useResult
$Res call({
 SecurityFailure failure
});


$SecurityFailureCopyWith<$Res> get failure;

}
/// @nodoc
class _$CoreFailure_SecurityCopyWithImpl<$Res>
    implements $CoreFailure_SecurityCopyWith<$Res> {
  _$CoreFailure_SecurityCopyWithImpl(this._self, this._then);

  final CoreFailure_Security _self;
  final $Res Function(CoreFailure_Security) _then;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(CoreFailure_Security(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as SecurityFailure,
  ));
}

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SecurityFailureCopyWith<$Res> get failure {
  
  return $SecurityFailureCopyWith<$Res>(_self.failure, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}

/// @nodoc


class CoreFailure_Io extends CoreFailure {
  const CoreFailure_Io({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreFailure_IoCopyWith<CoreFailure_Io> get copyWith => _$CoreFailure_IoCopyWithImpl<CoreFailure_Io>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreFailure_Io&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'CoreFailure.io(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreFailure_IoCopyWith<$Res> implements $CoreFailureCopyWith<$Res> {
  factory $CoreFailure_IoCopyWith(CoreFailure_Io value, $Res Function(CoreFailure_Io) _then) = _$CoreFailure_IoCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreFailure_IoCopyWithImpl<$Res>
    implements $CoreFailure_IoCopyWith<$Res> {
  _$CoreFailure_IoCopyWithImpl(this._self, this._then);

  final CoreFailure_Io _self;
  final $Res Function(CoreFailure_Io) _then;

/// Create a copy of CoreFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreFailure_Io(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$SecurityFailure {

 String get message;
/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SecurityFailureCopyWith<SecurityFailure> get copyWith => _$SecurityFailureCopyWithImpl<SecurityFailure>(this as SecurityFailure, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SecurityFailure&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'SecurityFailure(message: $message)';
}


}

/// @nodoc
abstract mixin class $SecurityFailureCopyWith<$Res>  {
  factory $SecurityFailureCopyWith(SecurityFailure value, $Res Function(SecurityFailure) _then) = _$SecurityFailureCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$SecurityFailureCopyWithImpl<$Res>
    implements $SecurityFailureCopyWith<$Res> {
  _$SecurityFailureCopyWithImpl(this._self, this._then);

  final SecurityFailure _self;
  final $Res Function(SecurityFailure) _then;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? message = null,}) {
  return _then(_self.copyWith(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SecurityFailure].
extension SecurityFailurePatterns on SecurityFailure {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SecurityFailure_SecretStore value)?  secretStore,TResult Function( SecurityFailure_KeyringEntryMissing value)?  keyringEntryMissing,TResult Function( SecurityFailure_SecretStoreMissing value)?  secretStoreMissing,TResult Function( SecurityFailure_InvalidSecret value)?  invalidSecret,TResult Function( SecurityFailure_Crypto value)?  crypto,TResult Function( SecurityFailure_Database value)?  database,TResult Function( SecurityFailure_Serialization value)?  serialization,TResult Function( SecurityFailure_InvalidMessageId value)?  invalidMessageId,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SecurityFailure_SecretStore() when secretStore != null:
return secretStore(_that);case SecurityFailure_KeyringEntryMissing() when keyringEntryMissing != null:
return keyringEntryMissing(_that);case SecurityFailure_SecretStoreMissing() when secretStoreMissing != null:
return secretStoreMissing(_that);case SecurityFailure_InvalidSecret() when invalidSecret != null:
return invalidSecret(_that);case SecurityFailure_Crypto() when crypto != null:
return crypto(_that);case SecurityFailure_Database() when database != null:
return database(_that);case SecurityFailure_Serialization() when serialization != null:
return serialization(_that);case SecurityFailure_InvalidMessageId() when invalidMessageId != null:
return invalidMessageId(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SecurityFailure_SecretStore value)  secretStore,required TResult Function( SecurityFailure_KeyringEntryMissing value)  keyringEntryMissing,required TResult Function( SecurityFailure_SecretStoreMissing value)  secretStoreMissing,required TResult Function( SecurityFailure_InvalidSecret value)  invalidSecret,required TResult Function( SecurityFailure_Crypto value)  crypto,required TResult Function( SecurityFailure_Database value)  database,required TResult Function( SecurityFailure_Serialization value)  serialization,required TResult Function( SecurityFailure_InvalidMessageId value)  invalidMessageId,}){
final _that = this;
switch (_that) {
case SecurityFailure_SecretStore():
return secretStore(_that);case SecurityFailure_KeyringEntryMissing():
return keyringEntryMissing(_that);case SecurityFailure_SecretStoreMissing():
return secretStoreMissing(_that);case SecurityFailure_InvalidSecret():
return invalidSecret(_that);case SecurityFailure_Crypto():
return crypto(_that);case SecurityFailure_Database():
return database(_that);case SecurityFailure_Serialization():
return serialization(_that);case SecurityFailure_InvalidMessageId():
return invalidMessageId(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SecurityFailure_SecretStore value)?  secretStore,TResult? Function( SecurityFailure_KeyringEntryMissing value)?  keyringEntryMissing,TResult? Function( SecurityFailure_SecretStoreMissing value)?  secretStoreMissing,TResult? Function( SecurityFailure_InvalidSecret value)?  invalidSecret,TResult? Function( SecurityFailure_Crypto value)?  crypto,TResult? Function( SecurityFailure_Database value)?  database,TResult? Function( SecurityFailure_Serialization value)?  serialization,TResult? Function( SecurityFailure_InvalidMessageId value)?  invalidMessageId,}){
final _that = this;
switch (_that) {
case SecurityFailure_SecretStore() when secretStore != null:
return secretStore(_that);case SecurityFailure_KeyringEntryMissing() when keyringEntryMissing != null:
return keyringEntryMissing(_that);case SecurityFailure_SecretStoreMissing() when secretStoreMissing != null:
return secretStoreMissing(_that);case SecurityFailure_InvalidSecret() when invalidSecret != null:
return invalidSecret(_that);case SecurityFailure_Crypto() when crypto != null:
return crypto(_that);case SecurityFailure_Database() when database != null:
return database(_that);case SecurityFailure_Serialization() when serialization != null:
return serialization(_that);case SecurityFailure_InvalidMessageId() when invalidMessageId != null:
return invalidMessageId(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String message)?  secretStore,TResult Function( String name,  String message)?  keyringEntryMissing,TResult Function( String message)?  secretStoreMissing,TResult Function( String message)?  invalidSecret,TResult Function( String message)?  crypto,TResult Function( String message)?  database,TResult Function( String message)?  serialization,TResult Function( String message)?  invalidMessageId,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SecurityFailure_SecretStore() when secretStore != null:
return secretStore(_that.message);case SecurityFailure_KeyringEntryMissing() when keyringEntryMissing != null:
return keyringEntryMissing(_that.name,_that.message);case SecurityFailure_SecretStoreMissing() when secretStoreMissing != null:
return secretStoreMissing(_that.message);case SecurityFailure_InvalidSecret() when invalidSecret != null:
return invalidSecret(_that.message);case SecurityFailure_Crypto() when crypto != null:
return crypto(_that.message);case SecurityFailure_Database() when database != null:
return database(_that.message);case SecurityFailure_Serialization() when serialization != null:
return serialization(_that.message);case SecurityFailure_InvalidMessageId() when invalidMessageId != null:
return invalidMessageId(_that.message);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String message)  secretStore,required TResult Function( String name,  String message)  keyringEntryMissing,required TResult Function( String message)  secretStoreMissing,required TResult Function( String message)  invalidSecret,required TResult Function( String message)  crypto,required TResult Function( String message)  database,required TResult Function( String message)  serialization,required TResult Function( String message)  invalidMessageId,}) {final _that = this;
switch (_that) {
case SecurityFailure_SecretStore():
return secretStore(_that.message);case SecurityFailure_KeyringEntryMissing():
return keyringEntryMissing(_that.name,_that.message);case SecurityFailure_SecretStoreMissing():
return secretStoreMissing(_that.message);case SecurityFailure_InvalidSecret():
return invalidSecret(_that.message);case SecurityFailure_Crypto():
return crypto(_that.message);case SecurityFailure_Database():
return database(_that.message);case SecurityFailure_Serialization():
return serialization(_that.message);case SecurityFailure_InvalidMessageId():
return invalidMessageId(_that.message);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String message)?  secretStore,TResult? Function( String name,  String message)?  keyringEntryMissing,TResult? Function( String message)?  secretStoreMissing,TResult? Function( String message)?  invalidSecret,TResult? Function( String message)?  crypto,TResult? Function( String message)?  database,TResult? Function( String message)?  serialization,TResult? Function( String message)?  invalidMessageId,}) {final _that = this;
switch (_that) {
case SecurityFailure_SecretStore() when secretStore != null:
return secretStore(_that.message);case SecurityFailure_KeyringEntryMissing() when keyringEntryMissing != null:
return keyringEntryMissing(_that.name,_that.message);case SecurityFailure_SecretStoreMissing() when secretStoreMissing != null:
return secretStoreMissing(_that.message);case SecurityFailure_InvalidSecret() when invalidSecret != null:
return invalidSecret(_that.message);case SecurityFailure_Crypto() when crypto != null:
return crypto(_that.message);case SecurityFailure_Database() when database != null:
return database(_that.message);case SecurityFailure_Serialization() when serialization != null:
return serialization(_that.message);case SecurityFailure_InvalidMessageId() when invalidMessageId != null:
return invalidMessageId(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class SecurityFailure_SecretStore extends SecurityFailure {
  const SecurityFailure_SecretStore({required this.message}): super._();
  

@override final  String message;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SecurityFailure_SecretStoreCopyWith<SecurityFailure_SecretStore> get copyWith => _$SecurityFailure_SecretStoreCopyWithImpl<SecurityFailure_SecretStore>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SecurityFailure_SecretStore&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'SecurityFailure.secretStore(message: $message)';
}


}

/// @nodoc
abstract mixin class $SecurityFailure_SecretStoreCopyWith<$Res> implements $SecurityFailureCopyWith<$Res> {
  factory $SecurityFailure_SecretStoreCopyWith(SecurityFailure_SecretStore value, $Res Function(SecurityFailure_SecretStore) _then) = _$SecurityFailure_SecretStoreCopyWithImpl;
@override @useResult
$Res call({
 String message
});




}
/// @nodoc
class _$SecurityFailure_SecretStoreCopyWithImpl<$Res>
    implements $SecurityFailure_SecretStoreCopyWith<$Res> {
  _$SecurityFailure_SecretStoreCopyWithImpl(this._self, this._then);

  final SecurityFailure_SecretStore _self;
  final $Res Function(SecurityFailure_SecretStore) _then;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(SecurityFailure_SecretStore(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SecurityFailure_KeyringEntryMissing extends SecurityFailure {
  const SecurityFailure_KeyringEntryMissing({required this.name, required this.message}): super._();
  

 final  String name;
@override final  String message;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SecurityFailure_KeyringEntryMissingCopyWith<SecurityFailure_KeyringEntryMissing> get copyWith => _$SecurityFailure_KeyringEntryMissingCopyWithImpl<SecurityFailure_KeyringEntryMissing>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SecurityFailure_KeyringEntryMissing&&(identical(other.name, name) || other.name == name)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,name,message);

@override
String toString() {
  return 'SecurityFailure.keyringEntryMissing(name: $name, message: $message)';
}


}

/// @nodoc
abstract mixin class $SecurityFailure_KeyringEntryMissingCopyWith<$Res> implements $SecurityFailureCopyWith<$Res> {
  factory $SecurityFailure_KeyringEntryMissingCopyWith(SecurityFailure_KeyringEntryMissing value, $Res Function(SecurityFailure_KeyringEntryMissing) _then) = _$SecurityFailure_KeyringEntryMissingCopyWithImpl;
@override @useResult
$Res call({
 String name, String message
});




}
/// @nodoc
class _$SecurityFailure_KeyringEntryMissingCopyWithImpl<$Res>
    implements $SecurityFailure_KeyringEntryMissingCopyWith<$Res> {
  _$SecurityFailure_KeyringEntryMissingCopyWithImpl(this._self, this._then);

  final SecurityFailure_KeyringEntryMissing _self;
  final $Res Function(SecurityFailure_KeyringEntryMissing) _then;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? message = null,}) {
  return _then(SecurityFailure_KeyringEntryMissing(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SecurityFailure_SecretStoreMissing extends SecurityFailure {
  const SecurityFailure_SecretStoreMissing({required this.message}): super._();
  

@override final  String message;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SecurityFailure_SecretStoreMissingCopyWith<SecurityFailure_SecretStoreMissing> get copyWith => _$SecurityFailure_SecretStoreMissingCopyWithImpl<SecurityFailure_SecretStoreMissing>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SecurityFailure_SecretStoreMissing&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'SecurityFailure.secretStoreMissing(message: $message)';
}


}

/// @nodoc
abstract mixin class $SecurityFailure_SecretStoreMissingCopyWith<$Res> implements $SecurityFailureCopyWith<$Res> {
  factory $SecurityFailure_SecretStoreMissingCopyWith(SecurityFailure_SecretStoreMissing value, $Res Function(SecurityFailure_SecretStoreMissing) _then) = _$SecurityFailure_SecretStoreMissingCopyWithImpl;
@override @useResult
$Res call({
 String message
});




}
/// @nodoc
class _$SecurityFailure_SecretStoreMissingCopyWithImpl<$Res>
    implements $SecurityFailure_SecretStoreMissingCopyWith<$Res> {
  _$SecurityFailure_SecretStoreMissingCopyWithImpl(this._self, this._then);

  final SecurityFailure_SecretStoreMissing _self;
  final $Res Function(SecurityFailure_SecretStoreMissing) _then;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(SecurityFailure_SecretStoreMissing(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SecurityFailure_InvalidSecret extends SecurityFailure {
  const SecurityFailure_InvalidSecret({required this.message}): super._();
  

@override final  String message;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SecurityFailure_InvalidSecretCopyWith<SecurityFailure_InvalidSecret> get copyWith => _$SecurityFailure_InvalidSecretCopyWithImpl<SecurityFailure_InvalidSecret>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SecurityFailure_InvalidSecret&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'SecurityFailure.invalidSecret(message: $message)';
}


}

/// @nodoc
abstract mixin class $SecurityFailure_InvalidSecretCopyWith<$Res> implements $SecurityFailureCopyWith<$Res> {
  factory $SecurityFailure_InvalidSecretCopyWith(SecurityFailure_InvalidSecret value, $Res Function(SecurityFailure_InvalidSecret) _then) = _$SecurityFailure_InvalidSecretCopyWithImpl;
@override @useResult
$Res call({
 String message
});




}
/// @nodoc
class _$SecurityFailure_InvalidSecretCopyWithImpl<$Res>
    implements $SecurityFailure_InvalidSecretCopyWith<$Res> {
  _$SecurityFailure_InvalidSecretCopyWithImpl(this._self, this._then);

  final SecurityFailure_InvalidSecret _self;
  final $Res Function(SecurityFailure_InvalidSecret) _then;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(SecurityFailure_InvalidSecret(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SecurityFailure_Crypto extends SecurityFailure {
  const SecurityFailure_Crypto({required this.message}): super._();
  

@override final  String message;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SecurityFailure_CryptoCopyWith<SecurityFailure_Crypto> get copyWith => _$SecurityFailure_CryptoCopyWithImpl<SecurityFailure_Crypto>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SecurityFailure_Crypto&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'SecurityFailure.crypto(message: $message)';
}


}

/// @nodoc
abstract mixin class $SecurityFailure_CryptoCopyWith<$Res> implements $SecurityFailureCopyWith<$Res> {
  factory $SecurityFailure_CryptoCopyWith(SecurityFailure_Crypto value, $Res Function(SecurityFailure_Crypto) _then) = _$SecurityFailure_CryptoCopyWithImpl;
@override @useResult
$Res call({
 String message
});




}
/// @nodoc
class _$SecurityFailure_CryptoCopyWithImpl<$Res>
    implements $SecurityFailure_CryptoCopyWith<$Res> {
  _$SecurityFailure_CryptoCopyWithImpl(this._self, this._then);

  final SecurityFailure_Crypto _self;
  final $Res Function(SecurityFailure_Crypto) _then;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(SecurityFailure_Crypto(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SecurityFailure_Database extends SecurityFailure {
  const SecurityFailure_Database({required this.message}): super._();
  

@override final  String message;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SecurityFailure_DatabaseCopyWith<SecurityFailure_Database> get copyWith => _$SecurityFailure_DatabaseCopyWithImpl<SecurityFailure_Database>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SecurityFailure_Database&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'SecurityFailure.database(message: $message)';
}


}

/// @nodoc
abstract mixin class $SecurityFailure_DatabaseCopyWith<$Res> implements $SecurityFailureCopyWith<$Res> {
  factory $SecurityFailure_DatabaseCopyWith(SecurityFailure_Database value, $Res Function(SecurityFailure_Database) _then) = _$SecurityFailure_DatabaseCopyWithImpl;
@override @useResult
$Res call({
 String message
});




}
/// @nodoc
class _$SecurityFailure_DatabaseCopyWithImpl<$Res>
    implements $SecurityFailure_DatabaseCopyWith<$Res> {
  _$SecurityFailure_DatabaseCopyWithImpl(this._self, this._then);

  final SecurityFailure_Database _self;
  final $Res Function(SecurityFailure_Database) _then;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(SecurityFailure_Database(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SecurityFailure_Serialization extends SecurityFailure {
  const SecurityFailure_Serialization({required this.message}): super._();
  

@override final  String message;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SecurityFailure_SerializationCopyWith<SecurityFailure_Serialization> get copyWith => _$SecurityFailure_SerializationCopyWithImpl<SecurityFailure_Serialization>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SecurityFailure_Serialization&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'SecurityFailure.serialization(message: $message)';
}


}

/// @nodoc
abstract mixin class $SecurityFailure_SerializationCopyWith<$Res> implements $SecurityFailureCopyWith<$Res> {
  factory $SecurityFailure_SerializationCopyWith(SecurityFailure_Serialization value, $Res Function(SecurityFailure_Serialization) _then) = _$SecurityFailure_SerializationCopyWithImpl;
@override @useResult
$Res call({
 String message
});




}
/// @nodoc
class _$SecurityFailure_SerializationCopyWithImpl<$Res>
    implements $SecurityFailure_SerializationCopyWith<$Res> {
  _$SecurityFailure_SerializationCopyWithImpl(this._self, this._then);

  final SecurityFailure_Serialization _self;
  final $Res Function(SecurityFailure_Serialization) _then;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(SecurityFailure_Serialization(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SecurityFailure_InvalidMessageId extends SecurityFailure {
  const SecurityFailure_InvalidMessageId({required this.message}): super._();
  

@override final  String message;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SecurityFailure_InvalidMessageIdCopyWith<SecurityFailure_InvalidMessageId> get copyWith => _$SecurityFailure_InvalidMessageIdCopyWithImpl<SecurityFailure_InvalidMessageId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SecurityFailure_InvalidMessageId&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'SecurityFailure.invalidMessageId(message: $message)';
}


}

/// @nodoc
abstract mixin class $SecurityFailure_InvalidMessageIdCopyWith<$Res> implements $SecurityFailureCopyWith<$Res> {
  factory $SecurityFailure_InvalidMessageIdCopyWith(SecurityFailure_InvalidMessageId value, $Res Function(SecurityFailure_InvalidMessageId) _then) = _$SecurityFailure_InvalidMessageIdCopyWithImpl;
@override @useResult
$Res call({
 String message
});




}
/// @nodoc
class _$SecurityFailure_InvalidMessageIdCopyWithImpl<$Res>
    implements $SecurityFailure_InvalidMessageIdCopyWith<$Res> {
  _$SecurityFailure_InvalidMessageIdCopyWithImpl(this._self, this._then);

  final SecurityFailure_InvalidMessageId _self;
  final $Res Function(SecurityFailure_InvalidMessageId) _then;

/// Create a copy of SecurityFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(SecurityFailure_InvalidMessageId(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
