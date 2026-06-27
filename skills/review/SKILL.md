# Code Review Skill

## Goal

Perform a comprehensive review of the current implementation.

Do not rewrite the implementation unless explicitly requested.

Focus on finding problems, risks, and opportunities for improvement.

---

## Review Checklist

### 1. Correctness

* Verify the implementation satisfies all requirements.
* Identify logical bugs.
* Check edge cases.
* Check null handling.
* Check unexpected inputs.
* Check failure scenarios.

---

### 2. Clean Code

Review:

* Naming
* Readability
* Duplication
* Method size
* Class responsibilities
* Complexity
* Dead code
* Magic numbers
* Code smells

---

### 3. SOLID Principles

Evaluate:

* Single Responsibility
* Open/Closed
* Liskov Substitution
* Interface Segregation
* Dependency Inversion

---

### 4. Architecture

Review:

* Layer separation
* Dependency direction
* Package organization
* Encapsulation
* Domain boundaries

Detect:

* Business logic inside controllers
* Repository leaking into controllers
* Tight coupling

---

### 5. Spring Boot Best Practices

Review:

* Transaction boundaries
* Dependency Injection
* Configuration
* Bean lifecycle
* Validation
* Exception handling

---

### 6. Database

Check:

* N+1 queries
* Missing indexes
* Inefficient queries
* Transaction scope
* Locking risks

---

### 7. Concurrency

Review:

* Thread safety
* Race conditions
* Shared mutable state
* Async behavior

---

### 8. Performance

Review:

* Algorithm complexity
* Memory usage
* Database round trips
* Object creation
* Collection operations

---

### 9. Security

Check:

* Authentication
* Authorization
* Input validation
* SQL Injection
* XSS
* Sensitive information leakage
* Logging sensitive data

---

### 10. Testing

Review:

* Test coverage
* Missing test cases
* Edge case tests
* Regression tests

---

## Output Format

### Summary

Short overall assessment.

---

### Critical Issues

Only issues that must be fixed.

---

### Improvements

Recommended improvements.

---

### Nice to Have

Optional enhancements.

---

### Overall Quality

Rate:

* Correctness
* Maintainability
* Performance
* Security
* Readability

Score each from 1-10.
