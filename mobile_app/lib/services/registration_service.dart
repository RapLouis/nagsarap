import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_endpoints.dart';
import 'api_service.dart';

/*
|--------------------------------------------------------------------------
| PHOTO VALIDATION RESULT
|--------------------------------------------------------------------------
*/

class ReferencePhotoValidationResult {
  final bool success;

  final String message;

  final String? code;

  const ReferencePhotoValidationResult({
    required this.success,
    required this.message,
    this.code,
  });
}

/*
|--------------------------------------------------------------------------
| REGISTRATION RESULT
|--------------------------------------------------------------------------
*/

class RegistrationResult {
  final bool success;

  final String message;

  final String? code;

  final Map<String, dynamic>? data;

  const RegistrationResult({
    required this.success,
    required this.message,
    this.code,
    this.data,
  });
}

class RegistrationService {
  RegistrationService._();

  static final RegistrationService instance =
      RegistrationService._();

  final ApiService _api =
      ApiService.instance;

  /*
  |--------------------------------------------------------------------------
  | VALIDATE REFERENCE PHOTO
  |--------------------------------------------------------------------------
  |
  | Runs BEFORE account registration.
  |
  */

  Future<ReferencePhotoValidationResult>
      validateReferencePhoto({
    required XFile profilePhoto,
  }) async {
    try {
      final formData = FormData.fromMap({
        'profile_photo':
            await MultipartFile.fromFile(
          profilePhoto.path,
          filename:
              profilePhoto.name,
        ),
      });

      final response =
          await _api.dio.post(
        ApiEndpoints
            .validateReferencePhoto,
        data: formData,
        options: Options(
          contentType:
              'multipart/form-data',
        ),
      );

      final dynamic raw =
          response.data;

      if (raw is! Map) {
        return const ReferencePhotoValidationResult(
          success: false,
          message:
              'Invalid response from the server.',
        );
      }

      final data =
          Map<String, dynamic>.from(
        raw,
      );

      return ReferencePhotoValidationResult(
        success:
            data['success'] == true,
        code:
            data['code']?.toString(),
        message:
            data['message']?.toString() ??
                'Photo validation completed.',
      );
    } on DioException catch (e) {
      return ReferencePhotoValidationResult(
        success: false,
        code:
            _extractCode(e),
        message:
            _extractErrorMessage(e),
      );
    } catch (e) {
      return const ReferencePhotoValidationResult(
        success: false,
        message:
            'Unable to validate the reference photo.',
      );
    }
  }

  /*
  |--------------------------------------------------------------------------
  | REGISTER
  |--------------------------------------------------------------------------
  */

  Future<RegistrationResult> register({
    required String studentNumber,
    required String surname,
    required String firstname,
    required String middlename,
    required String ext,
    required String email,
    required String password,
    required String passwordConfirmation,
    required XFile profilePhoto,
    required XFile form5,
  }) async {
    try {
      final formData =
          FormData.fromMap({
        'student_number':
            studentNumber.trim(),

        'surname':
            surname.trim(),

        'firstname':
            firstname.trim(),

        'middlename':
            middlename.trim().isEmpty
                ? null
                : middlename.trim(),

        'ext':
            ext.trim().isEmpty
                ? null
                : ext.trim(),

        'email':
            email.trim(),

        'password':
            password,

        'password_confirmation':
            passwordConfirmation,

        'device_name':
            'Flutter Android',

        'profile_photo':
            await MultipartFile.fromFile(
          profilePhoto.path,
          filename:
              profilePhoto.name,
        ),

        'form_5':
            await MultipartFile.fromFile(
          form5.path,
          filename:
              form5.name,
        ),
      });

      final response =
          await _api.dio.post(
        ApiEndpoints.register,
        data: formData,
        options: Options(
          contentType:
              'multipart/form-data',
        ),
      );

      final dynamic raw =
          response.data;

      if (raw is! Map) {
        return const RegistrationResult(
          success: false,
          message:
              'Invalid response from server.',
        );
      }

      final responseMap =
          Map<String, dynamic>.from(
        raw,
      );

      /*
      |--------------------------------------------------------------------------
      | YOUR LARAVEL RESPONSE STRUCTURE
      |--------------------------------------------------------------------------
      |
      | {
      |   success: true,
      |   code: "...",
      |   message: "...",
      |   data: {
      |     token: "...",
      |     user: {...},
      |     student: {...}
      |   }
      | }
      |
      */

      Map<String, dynamic> data = {};

      if (responseMap['data']
          is Map) {
        data =
            Map<String, dynamic>.from(
          responseMap['data']
              as Map,
        );
      }

      /*
      |--------------------------------------------------------------------------
      | SAVE SANCTUM TOKEN
      |--------------------------------------------------------------------------
      */

      final dynamic token =
          data['token'];

      if (token != null &&
          token
              .toString()
              .isNotEmpty) {
        await _api.saveToken(
          token.toString(),
        );
      }

      return RegistrationResult(
        success:
            responseMap['success'] ==
                    true ||
                response.statusCode ==
                    201,

        code:
            responseMap['code']
                ?.toString(),

        message:
            responseMap['message']
                    ?.toString() ??
                'Registration successful.',

        data: data,
      );
    } on DioException catch (e) {
      return RegistrationResult(
        success: false,
        code:
            _extractCode(e),
        message:
            _extractErrorMessage(e),
      );
    } catch (e) {
      return const RegistrationResult(
        success: false,
        message:
            'Unable to register. Please try again.',
      );
    }
  }

  /*
  |--------------------------------------------------------------------------
  | EXTRACT CODE
  |--------------------------------------------------------------------------
  */

  String? _extractCode(
    DioException exception,
  ) {
    final dynamic raw =
        exception.response?.data;

    if (raw is Map) {
      return raw['code']
          ?.toString();
    }

    return null;
  }

  /*
  |--------------------------------------------------------------------------
  | ERROR MESSAGE
  |--------------------------------------------------------------------------
  */

  String _extractErrorMessage(
    DioException exception,
  ) {
    final response =
        exception.response;

    if (response == null) {
      return 'Unable to connect to the server. Make sure Laravel and the required services are running.';
    }

    final dynamic raw =
        response.data;

    if (raw is Map) {
      final data =
          Map<String, dynamic>.from(
        raw,
      );

      /*
       * Direct message from Laravel.
       */

      if (data['message'] != null) {
        final String message =
            data['message']
                .toString();

        /*
         * Laravel validation often has a generic
         * "The given data was invalid" message.
         * Prefer the individual errors when available.
         */

        if (data['errors'] is! Map) {
          return message;
        }
      }

      /*
       * Laravel validation errors.
       */

      if (data['errors'] is Map) {
        final errors =
            Map<String, dynamic>.from(
          data['errors'] as Map,
        );

        if (errors.isNotEmpty) {
          final dynamic first =
              errors.values.first;

          if (first is List &&
              first.isNotEmpty) {
            return first.first
                .toString();
          }

          return first.toString();
        }
      }

      if (data['message'] != null) {
        return data['message']
            .toString();
      }
    }

    switch (
        response.statusCode) {
      case 401:
        return 'Authentication is required.';

      case 409:
        return 'This information is already registered.';

      case 413:
        return 'The selected file is too large.';

      case 422:
        return 'The selected information could not be validated.';

      case 500:
        return 'The server encountered an error.';

      default:
        return 'Unable to complete the request.';
    }
  }
}