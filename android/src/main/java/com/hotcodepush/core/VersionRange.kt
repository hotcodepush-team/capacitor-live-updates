package com.hotcodepush.core

/** A dotted numeric version; missing components are zero, pre-release and build metadata are ignored. */
class Version private constructor(val components: List<Int>) : Comparable<Version> {
    override fun compareTo(other: Version): Int {
        for (index in 0 until 3) {
            val difference = components[index].compareTo(other.components[index])
            if (difference != 0) return difference
        }
        return 0
    }

    override fun equals(other: Any?): Boolean = other is Version && components == other.components

    override fun hashCode(): Int = components.hashCode()

    companion object {
        fun parse(text: String): Version? {
            val core = text.split('-', '+').first()
            val parts = core.split('.')
            if (parts.isEmpty() || parts.size > 3) return null
            val numbers = parts.map { it.toIntOrNull() ?: return null }
            return Version(numbers + List(3 - numbers.size) { 0 })
        }
    }
}

/** The subset of npm's range syntax the three evaluators share: comparators, `x` wildcards, `||`. */
class VersionRange private constructor(private val alternatives: List<List<(Version) -> Boolean>>) {
    fun contains(version: Version): Boolean = alternatives.any { comparators -> comparators.all { it(version) } }

    fun contains(text: String): Boolean = Version.parse(text)?.let(::contains) ?: false

    companion object {
        fun parse(text: String): VersionRange? {
            val alternatives = text.split("||").map { alternative ->
                alternative.trim().split(' ').filter { it.isNotEmpty() }.flatMap { token -> parseToken(token) ?: return null }
            }
            return VersionRange(alternatives)
        }

        private fun parseToken(token: String): List<(Version) -> Boolean>? {
            val operators = listOf<Pair<String, (Version) -> (Version) -> Boolean>>(
                ">=" to { bound -> { it >= bound } },
                "<=" to { bound -> { it <= bound } },
                ">" to { bound -> { it > bound } },
                "<" to { bound -> { it < bound } },
                "=" to { bound -> { it == bound } },
            )
            for ((operator, make) in operators) {
                if (token.startsWith(operator)) {
                    val version = Version.parse(token.removePrefix(operator)) ?: return null
                    return listOf(make(version))
                }
            }
            return wildcard(token)
        }

        /** `2`, `2.x`, `2.*`, `2.4.x`: the range of every version with that prefix; `1.2.3` alone is exact. */
        private fun wildcard(token: String): List<(Version) -> Boolean>? {
            val parts = token.split('.')
            val fixed = parts.takeWhile { it != "x" && it != "X" && it != "*" }
            if (fixed.isEmpty() || fixed.size > 3) return null
            val numbers = fixed.map { it.toIntOrNull() ?: return null }
            if (numbers.size == 3 && parts.size == 3) {
                val version = Version.parse(token) ?: return null
                return listOf { it == version }
            }
            val lower = numbers + List(3 - numbers.size) { 0 }
            val upper = lower.toMutableList().also { it[numbers.size - 1] += 1; for (index in numbers.size until 3) it[index] = 0 }
            val lowerVersion = Version.parse(lower.joinToString(".")) ?: return null
            val upperVersion = Version.parse(upper.joinToString(".")) ?: return null
            return listOf({ it >= lowerVersion }, { it < upperVersion })
        }
    }
}
