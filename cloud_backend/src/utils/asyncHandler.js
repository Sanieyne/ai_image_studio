/**
 * Asynchronous Controller Wrapper
 * Eliminates repetitive try/catch blocks by forwarding unhandled promise rejections to next().
 */

export const asyncHandler = (fn) => (req, res, next) => {
  Promise.resolve(fn(req, res, next)).catch(next);
};
