// Smooth scrolling for navigation links
document.addEventListener('DOMContentLoaded', function() {
    // Handle navigation link clicks
    const navLinks = document.querySelectorAll('a[href^="#"]');
    
    navLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            
            const targetId = this.getAttribute('href');
            const targetSection = document.querySelector(targetId);
            
            if (targetSection) {
                const offsetTop = targetSection.offsetTop - 80; // Account for fixed navbar
                
                window.scrollTo({
                    top: offsetTop,
                    behavior: 'smooth'
                });
            }
        });
    });
    
    // Add scroll effect to navbar
    const navbar = document.querySelector('.navbar');
    let lastScrollTop = 0;
    
    window.addEventListener('scroll', function() {
        const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
        
        if (scrollTop > 100) {
            navbar.style.background = 'rgba(255, 255, 255, 0.95)';
            navbar.style.boxShadow = '0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)';
        } else {
            navbar.style.background = 'rgba(255, 255, 255, 0.8)';
            navbar.style.boxShadow = 'none';
        }
        
        lastScrollTop = scrollTop;
    });
    
    // Add animation to feature cards on scroll
    const observerOptions = {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    };
    
    const observer = new IntersectionObserver(function(entries) {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.style.opacity = '1';
                entry.target.style.transform = 'translateY(0)';
            }
        });
    }, observerOptions);
    
    // Observe feature cards
    const featureCards = document.querySelectorAll('.feature-card');
    featureCards.forEach(card => {
        card.style.opacity = '0';
        card.style.transform = 'translateY(20px)';
        card.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
        observer.observe(card);
    });
    
    // Observe steps
    const steps = document.querySelectorAll('.step');
    steps.forEach((step, index) => {
        step.style.opacity = '0';
        step.style.transform = 'translateY(20px)';
        step.style.transition = `opacity 0.6s ease ${index * 0.1}s, transform 0.6s ease ${index * 0.1}s`;
        observer.observe(step);
    });
    
    // Enhanced code block interactions
    const codeBlocks = document.querySelectorAll('.code-block, .code-window');
    codeBlocks.forEach(block => {
        // Add hover effects
        block.addEventListener('mouseenter', function() {
            this.style.transform = 'translateY(-2px)';
            this.style.boxShadow = '0 20px 25px -5px rgb(0 0 0 / 0.1), 0 10px 10px -5px rgb(0 0 0 / 0.04)';
        });

        block.addEventListener('mouseleave', function() {
            this.style.transform = 'translateY(0)';
            this.style.boxShadow = 'var(--shadow-lg)';
        });
    });
    
    // Add typing animation to hero code
    const codeContent = document.querySelector('.code-content pre code');
    if (codeContent) {
        const originalText = codeContent.textContent;
        codeContent.textContent = '';
        
        let i = 0;
        const typeWriter = () => {
            if (i < originalText.length) {
                codeContent.textContent += originalText.charAt(i);
                i++;
                setTimeout(typeWriter, 20);
            }
        };
        
        // Start typing animation after a delay
        setTimeout(typeWriter, 1000);
    }
    
    // Add parallax effect to hero section
    const hero = document.querySelector('.hero');
    if (hero) {
        window.addEventListener('scroll', () => {
            const scrolled = window.pageYOffset;
            const rate = scrolled * -0.5;
            hero.style.transform = `translateY(${rate}px)`;
        });
    }
    
    // Add hover effects to buttons
    const buttons = document.querySelectorAll('.btn');
    buttons.forEach(button => {
        button.addEventListener('mouseenter', function() {
            this.style.transform = 'translateY(-2px)';
        });
        
        button.addEventListener('mouseleave', function() {
            this.style.transform = 'translateY(0)';
        });
    });
    
    // Add stats counter animation
    const stats = document.querySelectorAll('.stat-number');
    const statsObserver = new IntersectionObserver(function(entries) {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const target = entry.target;
                const text = target.textContent;
                
                if (text === '100%') {
                    animateCounter(target, 0, 100, '%');
                } else if (text === '0') {
                    target.textContent = '0';
                    target.style.color = '#10b981';
                } else if (text === '⚡') {
                    target.style.animation = 'pulse 2s infinite';
                }
                
                statsObserver.unobserve(target);
            }
        });
    }, { threshold: 0.5 });
    
    stats.forEach(stat => {
        statsObserver.observe(stat);
    });
    
    function animateCounter(element, start, end, suffix = '') {
        let current = start;
        const increment = (end - start) / 50;
        const timer = setInterval(() => {
            current += increment;
            if (current >= end) {
                current = end;
                clearInterval(timer);
            }
            element.textContent = Math.floor(current) + suffix;
        }, 30);
    }

    // Initialize Prism.js and define Zig language
    initializePrism();
});

// Define Zig language for Prism.js and initialize highlighting
function initializePrism() {
    // Wait for Prism to be available
    if (typeof Prism === 'undefined') {
        setTimeout(initializePrism, 100);
        return;
    }

    // Define Zig language syntax highlighting
    Prism.languages.zig = {
        'comment': [
            {
                pattern: /(^|[^\\])\/\*[\s\S]*?(?:\*\/|$)/,
                lookbehind: true
            },
            {
                pattern: /(^|[^\\:])\/\/.*/,
                lookbehind: true
            }
        ],
        'string': [
            {
                pattern: /\\\\[^\\]*\\\\/,
                greedy: true
            },
            {
                pattern: /(["'])(?:\\(?:\r\n|[\s\S])|(?!\1)[^\\\r\n])*\1/,
                greedy: true
            }
        ],
        'keyword': /\b(?:const|var|fn|pub|try|catch|if|else|while|for|switch|return|defer|errdefer|unreachable|break|continue|struct|enum|union|error|test|comptime|inline|export|extern|packed|align|volatile|allowzero|noalias|async|await|suspend|resume|nosuspend|threadlocal)\b/,
        'builtin': /\b(?:u8|u16|u32|u64|u128|usize|i8|i16|i32|i64|i128|isize|f16|f32|f64|f128|bool|void|type|anytype|anyopaque|anyerror|noreturn|c_short|c_ushort|c_int|c_uint|c_long|c_ulong|c_longlong|c_ulonglong|c_longdouble|c_void|comptime_int|comptime_float)\b/,
        'function': /\b[a-zA-Z_]\w*(?=\s*\()/,
        'number': /\b(?:0[xX][\da-fA-F]+(?:\.[\da-fA-F]*)?(?:[pP][+-]?\d+)?|0[oO][0-7]+|0[bB][01]+|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)\b/,
        'boolean': /\b(?:true|false|null|undefined)\b/,
        'operator': /[+\-*\/%=!<>&|^~?:@]/,
        'punctuation': /[{}[\];(),.]/,
        'property': /\b[a-zA-Z_]\w*(?=\s*:)/,
        'attribute': /@[a-zA-Z_]\w*/
    };

    // Highlight all code blocks
    Prism.highlightAll();
}

// Add CSS animations
const style = document.createElement('style');
style.textContent = `
    @keyframes pulse {
        0%, 100% { transform: scale(1); }
        50% { transform: scale(1.1); }
    }
    
    @keyframes fadeInUp {
        from {
            opacity: 0;
            transform: translateY(30px);
        }
        to {
            opacity: 1;
            transform: translateY(0);
        }
    }
    
    .animate-fade-in-up {
        animation: fadeInUp 0.6s ease forwards;
    }
`;
document.head.appendChild(style);
