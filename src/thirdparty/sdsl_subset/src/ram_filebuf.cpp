#include "sdsl/ram_filebuf.hpp"

#include "sdsl/ram_fs.hpp"

namespace sdsl {

ram_filebuf::ram_filebuf() : std::stringbuf(std::ios_base::in | std::ios_base::out), m_mode(std::ios_base::in), m_is_open(false) {}

std::streambuf* ram_filebuf::open(const std::string& file, std::ios_base::openmode mode) {
    m_file = file;
    m_mode = mode;
    m_is_open = true;

    std::string content;
    if (ram_fs::exists(file)) {
        auto& data = ram_fs::content(file);
        content.assign(data.begin(), data.end());
    }

    if (mode & std::ios_base::trunc) {
        content.clear();
    }

    if ((mode & std::ios_base::app) && !content.empty()) {
        str(content);
        pubseekoff(0, std::ios_base::end, std::ios_base::out);
    } else {
        str(content);
        if (mode & std::ios_base::ate) {
            pubseekoff(0, std::ios_base::end, std::ios_base::out);
        } else {
            pubseekpos(0, std::ios_base::in | std::ios_base::out);
        }
    }

    return this;
}

bool ram_filebuf::is_open() const { return m_is_open; }

bool ram_filebuf::close() {
    if (!m_is_open) return false;

    if (m_mode & (std::ios_base::out | std::ios_base::app | std::ios_base::trunc)) {
        const auto s = str();
        ram_fs::store(m_file, ram_fs::content_type(s.begin(), s.end()));
    }

    m_is_open = false;
    return true;
}

} // namespace sdsl
