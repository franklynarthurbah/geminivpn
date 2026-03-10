/**
 * Input Validation Middleware
 * Uses express-validator for request validation
 */

import { body, param, validationResult } from 'express-validator';
import { Request, Response, NextFunction } from 'express';

/**
 * Handle validation errors
 */
export const handleValidationErrors = (
  req: Request,
  res: Response,
  next: NextFunction
): void => {
  const errors = validationResult(req);
  
  if (!errors.isEmpty()) {
    res.status(400).json({
      success: false,
      message: 'Validation failed',
      errors: errors.array().map(err => ({
        field: err.type === 'field' ? err.path : 'unknown',
        message: err.msg,
      })),
    });
    return;
  }
  
  next();
};

// ============================================================================
// Auth Validations
// ============================================================================

export const loginValidation = [
  body('email')
    .trim()
    .notEmpty()
    .withMessage('Email is required')
    .isEmail()
    .withMessage('Please enter a valid email address')
    // NOTE: do NOT call .normalizeEmail() here — login must accept the email
    // exactly as the user types it so bcrypt lookup matches the stored value.
    .isLength({ max: 255 })
    .withMessage('Email too long'),
  body('password')
    .notEmpty()
    .withMessage('Password is required')
    .isLength({ min: 8 })
    .withMessage('Password must be at least 8 characters'),
  handleValidationErrors,
];

export const registerValidation = [
  body('email')
    .trim()
    .notEmpty()
    .withMessage('Email is required')
    .isEmail()
    .withMessage('Please enter a valid email address')
    // NOTE: do NOT normalizeEmail() — it mutates gmail addresses (strips dots,
    // lowercases domain) which causes login mismatches. Store exactly as typed.
    .isLength({ max: 255 })
    .withMessage('Email too long'),
  body('password')
    .notEmpty()
    .withMessage('Password is required')
    .isLength({ min: 8 })
    .withMessage('Password must be at least 8 characters')
    // Removed: aggressive regex that blocked most user passwords silently.
    // Frontend now shows the "8 characters minimum" hint clearly.
    ,
  body('name')
    .optional()
    .trim()
    .isLength({ min: 1, max: 100 })
    .withMessage('Name must be between 1 and 100 characters'),
  handleValidationErrors,
];

export const refreshTokenValidation = [
  body('refreshToken')
    .notEmpty()
    .withMessage('Refresh token is required'),
  handleValidationErrors,
];

// ============================================================================
// VPN Validations
// ============================================================================

export const createClientValidation = [
  body('clientName')
    .trim()
    .notEmpty()
    .withMessage('Client name is required')
    .isLength({ min: 1, max: 100 })
    .withMessage('Client name must be between 1 and 100 characters'),
  body('serverId')
    .optional()
    .isUUID()
    .withMessage('Invalid server ID'),
  handleValidationErrors,
];

export const serverIdValidation = [
  param('serverId')
    .isUUID()
    .withMessage('Invalid server ID format'),
  handleValidationErrors,
];

// ============================================================================
// Payment Validations
// ============================================================================

export const createCheckoutValidation = [
  body('planType')
    .notEmpty()
    .withMessage('Plan type is required')
    .isIn(['MONTHLY', 'YEARLY', 'TWO_YEAR'])
    .withMessage('Invalid plan type'),
  body('successUrl')
    .notEmpty()
    .withMessage('Success URL is required')
    .isURL()
    .withMessage('Invalid URL format'),
  body('cancelUrl')
    .notEmpty()
    .withMessage('Cancel URL is required')
    .isURL()
    .withMessage('Invalid URL format'),
  handleValidationErrors,
];

// ============================================================================
// User Validations
// ============================================================================

export const updateProfileValidation = [
  body('name')
    .optional()
    .trim()
    .isLength({ min: 2, max: 100 })
    .withMessage('Name must be between 2 and 100 characters'),
  handleValidationErrors,
];

export const changePasswordValidation = [
  body('currentPassword')
    .notEmpty()
    .withMessage('Current password is required'),
  body('newPassword')
    .notEmpty()
    .withMessage('New password is required')
    .isLength({ min: 8 })
    .withMessage('Password must be at least 8 characters')
    .matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
    .withMessage('Password must contain uppercase, lowercase, and number'),
  handleValidationErrors,
];
