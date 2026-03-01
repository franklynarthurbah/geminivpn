/**
 * Winston Logger Configuration
 * Provides structured logging for the application
 */

import winston from 'winston';
import path from 'path';

const { combine, timestamp, printf, colorize, errors, json } = winston.format;

// Custom format for console output
const consoleFormat = printf(({ level, message, timestamp, stack, ...metadata }) => {
  let msg = `${timestamp} [${level}]: ${message}`;
  if (Object.keys(metadata).length > 0) {
    msg += ` ${JSON.stringify(metadata)}`;
  }
  if (stack) {
    msg += `\n${stack}`;
  }
  return msg;
});

// Determine log level from environment
const logLevel = process.env.LOG_LEVEL || 'info';

// Create logger instance
export const logger = winston.createLogger({
  level: logLevel,
  defaultMeta: {
    service: 'geminivpn-backend',
    environment: process.env.NODE_ENV || 'development',
  },
  transports: [
    // Console transport (with colors in development)
    new winston.transports.Console({
      format: combine(
        timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
        colorize(),
        consoleFormat
      ),
    }),
  ],
});

// Add file transport in production
if (process.env.NODE_ENV === 'production') {
  const logFile = process.env.LOG_FILE || 'logs/app.log';
  
  // JSON format for production logging
  logger.add(new winston.transports.File({
    filename: logFile,
    format: combine(
      timestamp(),
      errors({ stack: true }),
      json()
    ),
  }));
  
  // Separate error log
  logger.add(new winston.transports.File({
    filename: 'logs/error.log',
    level: 'error',
    format: combine(
      timestamp(),
      errors({ stack: true }),
      json()
    ),
  }));
}

// Stream for Morgan HTTP logging integration
export const loggerStream = {
  write: (message: string) => {
    logger.info(message.trim());
  },
};
