#ifndef INCLUDED_SDSL_RAM_FSTREAMBUF
#define INCLUDED_SDSL_RAM_FSTREAMBUF

#include <ios>
#include <streambuf>
#include <string>
#include <sstream>

namespace sdsl {

class ram_filebuf : public std::stringbuf
{
  private:
    std::string m_file;
    std::ios_base::openmode m_mode;
    bool m_is_open;

  public:
    ram_filebuf();

    std::streambuf* open(const std::string& file, std::ios_base::openmode mode);
    bool is_open() const;
    bool close();
};

} // namespace sdsl

#endif
