const fs = require('fs')
const { execSync } = require('child_process')

const { logCommand, logCommandError, logInfo } = require('./logger.js')

/**
 * Checks if two 0x addresses are equal, regardless of case.
 * If either address is null, returns false.
 *
 * @param {string} addrA - The first address
 * @param {string} addrB - The second address
 * @returns {bool} Whether the addresses are equal
 */
const areEqualAddresses = (addrA, addrB) => {
  if (!addrA || !addrB) {
    return false
  }
  return addrA.toLowerCase() === addrB.toLowerCase()
}

/**
 * Asserts that a condition is true. If not, logs an error message and exits the process.
 *
 * @param {bool} condition - The condition to assert
 * @param {string} message - The error message to log if the condition is false
 */
const assertCondition = (condition, message) => {
  if (!condition) {
    console.error(message)
    process.exit(1)
  }
}

/**
 * Logs an error message and exits the process.
 *
 * @param {string} message - The error message to log
 */
const exitWithError = (message) => {
  assertCondition(false, message)
}

/**
 * Creates a directory recursively if it doesn't exist.
 * No-op if the directory already exists.
 *
 * @param {string[]} dirNames - The names of the directories to create
 * @returns {string} The path of the directory (whether it was created or not)
 */
const createDir = (...dirNames) => {
  const dirPath = dirNames.join('/')
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true })
  }
  return dirPath
}

/**
 * Runs a command and returns its output.
 * If the command fails, exits the process.
 *
 * @param {string} command - The command to run
 * @returns {string} The output of the command
 */
const getCommandOutput = (command, exitOnError = true) => {
  try {
    const output = execSync(command)
    return output.toString().trim()
  } catch (error) {
    logCommandError(command)
    if (exitOnError) {
      process.exit(1)
    }
    return null
  }
}

/**
 * Runs a command (printing its output to the console). If the command fails, logs an error message.
 *
 * @param {string} command - The command to run
 * @returns {bool} Whether the command succeeded
 */
const runCommand = (command, exitOnError = true) => {
  try {
    logCommand(`${command}`)
    execSync(command, { stdio: 'inherit' })
    return true
  } catch (error) {
    logCommandError(command)
    if (exitOnError) {
      process.exit(1)
    }
    return false
  }
}

const syncSleep = (seconds, reason) => {
  let logMsg = `Sleeping for ${seconds} seconds`
  if (reason) {
    logMsg += `: ${reason}`
  }
  logInfo(logMsg)
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, seconds * 1000)
}

module.exports = {
  areEqualAddresses,
  assertCondition,
  createDir,
  exitWithError,
  getCommandOutput,
  runCommand,
  syncSleep,
}
