/**
 * Winston Logger — GeminiVPN
 *
 * CRITICAL FIX: Log files use ABSOLUTE paths (/var/log/geminivpn/).
 * The Docker image runs as the `nodejs` user (uid 1001) which has no write
 * permission to /app/.  Relative paths like 'logs/app.log' would resolve to
 * /app/logs/ and fail with EACCES, crashing the container on startup.
 * /var/log/geminivpn/ is created and chowned to nodejs in Dockerfile.
 */

import winston from 'winston';

const { combine, timestamp, printf, colorize, errors, json } = winston.format;

const consoleFormat = printf(({ level, message, timestamp, stack, ...meta }) => {
  let msg = `${timestamp} [${level}]: ${message}`;
  if (Object.keys(meta).length > 0) msg += ` ${JSON.stringify(meta)}`;
  if (stack) msg += `\n${stack}`;
  return msg;
});

const logLevel = process.env.LOG_LEVEL || 'info';

export const logger = winston.createLogger({
  level: logLevel,
  defaultMeta: {
    service: 'geminivpn-backend',
    environment: process.env.NODE_ENV || 'development',
  },
  transports: [
    new winston.transports.Console({
      format: combine(
        timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
        colorize(),
        consoleFormat,
      ),
    }),
  ],
});

// File transport — production only, using absolute paths the nodejs user can write to.
// The Dockerfile creates /var/log/geminivpn and chowns it to nodejs before USER nodejs.
if (process.env.NODE_ENV === 'production') {
  const LOG_DIR = '/var/log/geminivpn';

  logger.add(new winston.transports.File({
    filename: `${LOG_DIR}/app.log`,
    format: combine(timestamp(), errors({ stack: true }), json()),
  }));

  logger.add(new winston.transports.File({
    filename: `${LOG_DIR}/error.log`,
    level: 'error',
    format: combine(timestamp(), errors({ stack: true }), json()),
  }));
}

export const loggerStream = {
  write: (message: string) => { logger.info(message.trim()); },
};
