/**
 * Input Validation Middleware — GeminiVPN
 * 
 * FIXES APPLIED:
 *  1. Login: removed .isEmail() — login accepts any non-empty string as email
 *     (isEmail() can reject edge-case valid emails, causing login failures)
 *  2. Register: removed .normalizeEmail() and password regex (caused login mismatches)
 *  3. All: error messages are clear and user-visible
 */

import { body, param, validationResult } from 'express-validator';
import { Request, Response, NextFunction } from 'express';

export const handleValidationErrors = (
  req: Request,
  res: Response,
  next: NextFunction
): void => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    res.status(400).json({
      success: false,
      message: errors.array()[0].msg,  // Return the FIRST error message directly (not 'Validation failed')
      errors: errors.array().map(err => ({
        field: err.type === 'field' ? err.path : 'unknown',
        message: err.msg,
      })),
    });
    return;
  }
  next();
};

// ── Auth ──────────────────────────────────────────────────────────────────────

export const loginValidation = [
  body('email')
    .trim()
    .notEmpty().withMessage('Email is required')
    .isLength({ max: 255 }).withMessage('Email too long'),
    // NOTE: NOT using .isEmail() here — the email was validated at register.
    // Using .isEmail() on login would block edge-case valid stored emails.
  body('password')
    .notEmpty().withMessage('Password is required')
    .isLength({ min: 1 }).withMessage('Password is required'),
    // NOTE: no min:8 check on login — the DB lookup handles auth, not the validator.
    // Adding min:8 here would block users who somehow have shorter passwords.
  handleValidationErrors,
];

export const registerValidation = [
  body('email')
    .trim()
    .notEmpty().withMessage('Email is required')
    .isEmail().withMessage('Please enter a valid email address')
    // NOTE: NOT calling .normalizeEmail() — it mutates addresses (gmail dot removal)
    // causing register email ≠ login email ≠ stored email mismatches.
    .isLength({ max: 255 }).withMessage('Email too long'),
  body('password')
    .notEmpty().withMessage('Password is required')
    .isLength({ min: 8 }).withMessage('Password must be at least 8 characters'),
    // NOTE: Password complexity regex REMOVED — it rejected valid passwords silently.
    // The frontend now shows "minimum 8 characters" hint clearly.
  body('name')
    .optional()
    .trim()
    .isLength({ min: 1, max: 100 }).withMessage('Name must be between 1 and 100 characters'),
  handleValidationErrors,
];

export const refreshTokenValidation = [
  body('refreshToken')
    .notEmpty().withMessage('Refresh token is required'),
  handleValidationErrors,
];

// ── VPN ───────────────────────────────────────────────────────────────────────

export const createClientValidation = [
  body('clientName')
    .trim()
    .notEmpty().withMessage('Client name is required')
    .isLength({ min: 1, max: 100 }).withMessage('Client name must be between 1 and 100 characters'),
  body('serverId')
    .optional()
    .isUUID().withMessage('Invalid server ID'),
  handleValidationErrors,
];

export const serverIdValidation = [
  param('serverId')
    .isUUID().withMessage('Invalid server ID format'),
  handleValidationErrors,
];

// ── Payment ───────────────────────────────────────────────────────────────────

export const createCheckoutValidation = [
  body('planType')
    .notEmpty().withMessage('Plan type is required')
    .isIn(['MONTHLY', 'YEARLY', 'TWO_YEAR']).withMessage('Invalid plan type'),
  body('successUrl')
    .notEmpty().withMessage('Success URL is required')
    .isURL().withMessage('Invalid URL format'),
  body('cancelUrl')
    .notEmpty().withMessage('Cancel URL is required')
    .isURL().withMessage('Invalid URL format'),
  handleValidationErrors,
];

// ── User ──────────────────────────────────────────────────────────────────────

export const updateProfileValidation = [
  body('name')
    .optional()
    .trim()
    .isLength({ min: 2, max: 100 }).withMessage('Name must be between 2 and 100 characters'),
  handleValidationErrors,
];

export const changePasswordValidation = [
  body('currentPassword')
    .notEmpty().withMessage('Current password is required'),
  body('newPassword')
    .notEmpty().withMessage('New password is required')
    .isLength({ min: 8 }).withMessage('New password must be at least 8 characters')
    .matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
    .withMessage('New password must contain an uppercase letter, lowercase letter, and number'),
  handleValidationErrors,
];
